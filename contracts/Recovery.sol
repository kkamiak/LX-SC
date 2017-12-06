pragma solidity ^0.4.11;

import './User.sol';
import './adapters/Roles2LibraryAdapter.sol';


contract Recovery is Roles2LibraryAdapter {

    event UserRecovered(address prevUser, address newUser, User userContract);

    function Recovery(address _roles2Library) Roles2LibraryAdapter(_roles2Library) public {}

    function recoverUser(User _userContract, address _newAddress) public auth() returns(bool) {
        address prev = _userContract.contractOwner();
        if (!_userContract.recoverUser(_newAddress)){
            revert();
        }
        UserRecovered(prev, _newAddress, _userContract);
        return true;
    }

}
