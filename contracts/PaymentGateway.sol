pragma solidity ^0.4.11;

import './adapters/MultiEventsHistoryAdapter.sol';
import './adapters/Roles2LibraryAndERC20LibraryAdapter.sol';
import './adapters/StorageAdapter.sol';


contract ERC20BalanceInterface {
    function balanceOf(address _address) public view returns(uint);
}

contract BalanceHolderInterface {
    function deposit(address _from, uint _value, address _contract) public returns(bool);
    function withdraw(address _to, uint _value, address _contract) public returns(bool);
}

contract PaymentGateway is StorageAdapter, MultiEventsHistoryAdapter, Roles2LibraryAndERC20LibraryAdapter {
    StorageInterface.Address balanceHolder;
    StorageInterface.AddressAddressUIntMapping balances; // contract => user => balance
    StorageInterface.Address feeAddress;
    StorageInterface.AddressUIntMapping fees; // 10000 is 100%.

    event FeeSet(address indexed self, address indexed contractAddress, uint feePercent);
    event Deposited(address indexed self, address indexed contractAddress, address indexed by, uint value);
    event Withdrawn(address indexed self, address indexed contractAddress, address indexed by, uint value);
    event Transferred(address indexed self, address indexed contractAddress, address from, address indexed to, uint value);

    modifier notNull(uint _value) {
        if (!_notNull(_value, false)) {
            return;
        }
        _;
    }

    function _notNull(uint _value, bool _throws) internal returns(bool) {
        if (_value == 0) {
            if (_throws) {
                revert();
            }
            _emitError("Value is empty");
            return false;
        }
        return true;
    }

    function PaymentGateway(Storage _store, bytes32 _crate, address _roles2Library, address _erc20Library)
        public
        StorageAdapter(_store, _crate)
        Roles2LibraryAndERC20LibraryAdapter(_roles2Library, _erc20Library)
    {
        balanceHolder.init('balanceHolder');
        balances.init('balances');
        feeAddress.init('feeAddress');
        fees.init('fees');
    }

    function setupEventsHistory(address _eventsHistory) external auth() returns(bool) {  // only owner
        if (getEventsHistory() != 0x0) {
            return false;
        }
        _setEventsHistory(_eventsHistory);
        return true;
    }

    function setBalanceHolder(address _balanceHolder) external auth() returns(bool) {  // only owner
        store.set(balanceHolder, _balanceHolder);
        return true;
    }

    function setFeeAddress(address _feeAddress) external auth() returns(bool) {  // only owner
        store.set(feeAddress, _feeAddress);
        return true;
    }

    function setFeePercent(uint _feePercent, address _contract)
        external
        auth()  // only owner
        onlySupportedContract(_contract)
    returns(bool) {
        if (_feePercent >= 10000) {
            return false;
        }
        store.set(fees, _contract, _feePercent);
        _emitFeeSet(_feePercent, _contract);
        return true;
    }

    function getFeePercent(address _contract) public view returns(uint) {
        return store.get(fees, _contract);
    }

    function deposit(uint _value, address _contract)
        public
        notNull(_value)
        onlySupportedContract(_contract)
    returns(bool) {
        if (getBalanceOf(msg.sender, _contract) < _value) {
            _emitError("Not enough balance to deposit");
            return false;
        }
        uint balanceBefore = getBalanceOf(getBalanceHolder(), _contract);
        if (!getBalanceHolder().deposit(msg.sender, _value, _contract)) {
            _emitError("Deposit failed");
            return false;
        }
        uint depositedAmount = _safeSub(getBalanceOf(getBalanceHolder(), _contract), balanceBefore);
        store.set(balances, _contract, msg.sender, _safeAdd(getBalance(msg.sender, _contract), depositedAmount));
        _emitDeposited(msg.sender, depositedAmount, _contract);
        return true;
    }

    function withdraw(uint _value, address _contract)
        public
        notNull(_value)
    returns(bool) {
        return _withdraw(msg.sender, _value, _contract);
    }

    function _withdraw(address _from, uint _value, address _contract) internal returns(bool) {
        if (getBalance(_from, _contract) < _value) {
            _emitError("Not enough balance to withdraw");
            return false;
        }
        uint balanceBefore = getBalanceOf(getBalanceHolder(), _contract);
        if (!getBalanceHolder().withdraw(_from, _value, _contract)) {
            _emitError("Withdrawal failed");
            return false;
        }
        uint withdrawnAmount = _safeSub(balanceBefore, getBalanceOf(getBalanceHolder(), _contract));
        store.set(balances, _contract, _from, _safeSub(getBalance(_from, _contract), withdrawnAmount));
        _emitWithdrawn(_from, _value, _contract);
        return true;
    }

    // Will be optimized later if used.
    function transfer(address _from, address _to, uint _value, address _contract) public returns(bool) {
        return transferWithFee(_from, _to, _value, _value, 0, _contract);
    }

    function transferWithFee(
        address _from,
        address _to,
        uint _value,
        uint _feeFromValue,
        uint _additionalFee,
        address _contract
    )
    public
    returns(bool) {
        address[] memory toArray = new address[](1);
        toArray[0] = _to;
        uint[] memory valueArray = new uint[](1);
        valueArray[0] = _value;
        return transferToMany(_from, toArray, valueArray, _feeFromValue, _additionalFee, _contract);
    }

    function transferToMany(
        address _from,
        address[] _to,
        uint[] _value,
        uint _feeFromValue,
        uint _additionalFee,
        address _contract
    )
        public
        auth()  // only payment processor
        notNull(uint(_from))
        onlySupportedContract(_contract)
    returns(bool) {
        if (_to.length != _value.length) {
            _emitError("Invalid array arguments");
            return false;
        }
        uint total = 0;
        for (uint i = 0; i < _to.length; i++) {
            _addBalance(_to[i], _value[i], _contract);
            _emitTransferred(_from, _to[i], _value[i], _contract);
            total = _safeAdd(total, _value[i]);
        }
        uint fee = _safeAdd(calculateFee(_feeFromValue, _contract), _additionalFee);
        if (fee > 0 && getFeeAddress() != 0x0) {
            _addBalance(getFeeAddress(), fee, _contract);
            _emitTransferred(_from, getFeeAddress(), fee, _contract);
            total = _safeAdd(total, fee);
        }
        _subBalance(_from, total, _contract);
        return true;
    }

    function transferAll(
        address _from,
        address _to,
        uint _value,
        address _change,
        uint _feeFromValue,
        uint _additionalFee,
        address _contract
    )
        external
        auth()  // only payment processor
        notNull(uint(_from))
        onlySupportedContract(_contract)
    returns(bool) {
        uint total = _value;
        _addBalance(_to, _value, _contract);
        _emitTransferred(_from, _to, _value, _contract);
        uint fee = _safeAdd(calculateFee(_feeFromValue, _contract), _additionalFee);
        if (fee > 0 && getFeeAddress() != 0x0) {
            _addBalance(getFeeAddress(), fee, _contract);
            _emitTransferred(_from, getFeeAddress(), fee, _contract);
            total = _safeAdd(total, fee);
        }
        uint change = _safeSub(getBalance(_from, _contract), total);
        if (change != 0) {
            _addBalance(_change, change, _contract);
            _emitTransferred(_from, _change, change, _contract);
            total = _safeAdd(total, change);
        }
        _subBalance(_from, total, _contract);
        return true;
    }

    function transferFromMany(
        address[] _from,
        address _to,
        uint[] _value,
        address _contract
    )
        external
        auth()  // only payment processor
        notNull(uint(_to))
        onlySupportedContract(_contract)
    returns(bool) {
        if (_from.length != _value.length) {
            _emitError("Invalid array arguments");
            return false;
        }
        uint total = 0;
        for (uint i = 0; i < _from.length; i++) {
            _subBalance(_from[i], _value[i], _contract);
            _emitTransferred(_from[i], _to, _value[i], _contract);
            total = _safeAdd(total, _value[i]);
        }
        _addBalance(_to, total, _contract);
        return true;
    }

    function forwardFee(uint _value, address _contract)
        public
        notNull(_value)
    returns(bool) {
        if (getFeeAddress() == 0x0) {
            return false;
        }
        return _withdraw(getFeeAddress(), _value, _contract);
    }

    function getBalance(address _address, address _contract) public view returns(uint) {
        return store.get(balances, _contract, _address);
    }

    function getBalanceOf(address _address, address _contract) public view returns(uint) {
        return ERC20BalanceInterface(_contract).balanceOf(_address);
    }

    function calculateFee(uint _value, address _contract) public view returns(uint) {
        uint feeRaw = _value * getFeePercent(_contract);
        return (feeRaw / 10000) + (feeRaw % 10000 == 0 ? 0 : 1);
    }

    function getFeeAddress() public view returns(address) {
        return store.get(feeAddress);
    }

    function getBalanceHolder() public view returns(BalanceHolderInterface) {
        return BalanceHolderInterface(store.get(balanceHolder));
    }


    // HELPERS

    function _assert(bool _assertion) internal pure {
        if (!_assertion) {
            revert();
        }
    }

    function _safeSub(uint _a, uint _b) internal pure returns(uint) {
        _assert(_b <= _a);
        return _a - _b;
    }

    function _safeAdd(uint _a, uint _b) internal pure returns(uint) {
        uint c = _a + _b;
        _assert(c >= _a);
        return c;
    }

    function _addBalance(address _to, uint _value, address _contract) internal {
        _notNull(uint(_to), true);
        _notNull(_value, true);
        store.set(balances, _contract, _to, _safeAdd(getBalance(_to, _contract), _value));
    }

    function _subBalance(address _from, uint _value, address _contract) internal {
        _notNull(uint(_from), true);
        _notNull(_value, true);
        store.set(balances, _contract, _from, _safeSub(getBalance(_from, _contract), _value));
    }



    // EVENTS

    function _emitFeeSet(uint _feePercent, address _contract) internal {
        PaymentGateway(getEventsHistory()).emitFeeSet(_feePercent, _contract);
    }

    function _emitDeposited(address _by, uint _value, address _contract) internal {
        PaymentGateway(getEventsHistory()).emitDeposited(_by, _value, _contract);
    }

    function _emitWithdrawn(address _by, uint _value, address _contract) internal {
        PaymentGateway(getEventsHistory()).emitWithdrawn(_by, _value, _contract);
    }

    function _emitTransferred(address _from, address _to, uint _value, address _contract) internal {
        PaymentGateway(getEventsHistory()).emitTransferred(_from, _to, _value, _contract);
    }

    function emitFeeSet(uint _feePercent, address _contract) public {
        FeeSet(_self(), _contract, _feePercent);
    }

    function emitDeposited(address _by, uint _value, address _contract) public {
        Deposited(_self(), _contract, _by, _value);
    }

    function emitWithdrawn(address _by, uint _value, address _contract) public {
        Withdrawn(_self(), _contract, _by, _value);
    }

    function emitTransferred(address _from, address _to, uint _value, address _contract) public {
        Transferred(_self(), _contract, _from, _to, _value);
    }

}
