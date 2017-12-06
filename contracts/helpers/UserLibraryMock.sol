pragma solidity ^0.4.11;

contract UserLibraryMock {
    uint addRoleCalls = 0;
    uint setManyCalls = 0; 

    function getCalls() constant returns(uint, uint){
        return (addRoleCalls, setManyCalls);
    }

    function addRole(address, bytes32) constant returns(bool) {
        addRoleCalls++;
        return true;
    }

    function setMany(address, uint, uint[], uint[]) returns(bool) {
        setManyCalls++;
        return true;
    }
}
