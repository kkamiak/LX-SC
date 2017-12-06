pragma solidity ^0.4.11;

import './adapters/MultiEventsHistoryAdapter.sol';
import './adapters/Roles2LibraryAdapter.sol';
import './adapters/StorageAdapter.sol';


contract ERC20Library is StorageAdapter, MultiEventsHistoryAdapter, Roles2LibraryAdapter {
    StorageInterface.AddressesSet contracts;

    event ContractAdded(address indexed self, address indexed contractAddress);
    event ContractRemoved(address indexed self, address indexed contractAddress);

    function ERC20Library(Storage _store, bytes32 _crate, address _roles2Library)
        public
        StorageAdapter(_store, _crate)
        Roles2LibraryAdapter(_roles2Library)
    {
        contracts.init('contracts');
    }

    function setupEventsHistory(address _eventsHistory) external auth() returns(bool) {
        if (getEventsHistory() != 0x0) {
            return false;
        }
        _setEventsHistory(_eventsHistory);
        return true;
    }

    function count() public view returns(uint) {
        return store.count(contracts);
    }

    function includes(address _contract) public view returns(bool) {
        return store.includes(contracts, _contract);
    }

    function getContracts() public view returns(address[]) {
        return store.get(contracts);
    }

    function getContract(uint _index) public view returns(address) {
        return store.get(contracts, _index);
    }

    function addContract(address _address) external auth() returns(bool) {
        if (includes(_address)) {
            return false;
        }
        store.add(contracts, _address);
        _emitContractAdded(_address);
        return true;
    }

    function removeContract(address _address) external auth() returns(bool) {
        if (!includes(_address)) {
            return false;
        }
        store.remove(contracts, _address);
        _emitContractRemoved(_address);
        return true;
    }

    function _emitContractAdded(address _address) internal {
        ERC20Library(getEventsHistory()).emitContractAdded(_address);
    }

    function _emitContractRemoved(address _address) internal {
        ERC20Library(getEventsHistory()).emitContractRemoved(_address);
    }

    function emitContractAdded(address _address) public {
        ContractAdded(_self(), _address);
    }

    function emitContractRemoved(address _address) public {
        ContractRemoved(_self(), _address);
    }
}
