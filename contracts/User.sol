pragma solidity ^0.4.11;

import './User.sol';
import './UserProxy.sol';
import './base/Owned.sol';

contract User is Owned {
    UserProxy userProxy;
    address recoveryContract;

    modifier onlyRecoveryContract() {
        if (recoveryContract == msg.sender) {
            _;
        }
    }

    function User(address _owner, address _recoveryContract) public Owned() {
        userProxy = new UserProxy();
        recoveryContract = _recoveryContract;
        contractOwner = _owner;
    }

    function setUserProxy(UserProxy _userProxy) public onlyContractOwner() returns(bool) {
        userProxy = _userProxy;
        return true;
    }

    function getUserProxy() public constant returns(address) {
        return userProxy;
    }

    function setRecoveryContract(address _recoveryContract) public onlyContractOwner() returns(bool) {
        recoveryContract = _recoveryContract;
        return true;
    }

    function forward(
        address _destination,
        bytes _data,
        uint _value,
        bool _throwOnFailedCall
    )
        public
        onlyContractOwner()
    returns(bytes32) {
        return userProxy.forward(_destination, _data, _value, _throwOnFailedCall);
    }

    function recoverUser(address newAddress) onlyRecoveryContract() public returns(bool) {
        contractOwner = newAddress;
        return true;
    }

}
