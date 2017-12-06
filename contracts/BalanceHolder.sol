pragma solidity ^0.4.11;

import './adapters/Roles2LibraryAdapter.sol';
import './base/ERC20Interface.sol';

contract BalanceHolder is Roles2LibraryAdapter {
    function BalanceHolder(address _roles2Library) public Roles2LibraryAdapter(_roles2Library) {}

    function deposit(address _from, uint _value, ERC20Interface _contract) external auth() returns(bool) {
        return _contract.transferFrom(_from, this, _value);
    }

    function withdraw(address _to, uint _value, ERC20Interface _contract) external auth() returns(bool) {
        return _contract.transfer(_to, _value);
    }
}
