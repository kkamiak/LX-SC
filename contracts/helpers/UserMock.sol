pragma solidity ^0.4.11;

contract UserMock {

    address public contractOwner;
    uint public recoverUserCalls;

    function recoverUser(address _newAddress) external returns (bool) {
        contractOwner = _newAddress;
        recoverUserCalls++;
        return true;
    }

    function setContractOwner(address _newOwner) external returns (bool){
        contractOwner = _newOwner;
        return true;
    }

}
