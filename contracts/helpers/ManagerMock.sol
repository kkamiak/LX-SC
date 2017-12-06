pragma solidity ^0.4.11;

contract ManagerMock {
    bool denied;

    function deny() {
        denied = true;
    }

    function isAllowed(address, bytes32) constant returns(bool) {
        if (denied) {
            denied = false;
            return false;
        }
        return true;
    }
}
