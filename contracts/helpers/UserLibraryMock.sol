pragma solidity ^0.4.11;


contract UserLibraryMock {

    uint addRoleCalls = 0;
    uint setManyCalls = 0;

    function getCalls() public view returns (uint, uint){
        return (addRoleCalls, setManyCalls);
    }

    function addRole(address, bytes32) public returns (bool) {
        addRoleCalls++;
        return true;
    }

    function setMany(address, uint, uint[], uint[]) public returns (bool) {
        setManyCalls++;
        return true;
    }
}
