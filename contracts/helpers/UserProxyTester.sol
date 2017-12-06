pragma solidity ^0.4.11;

contract UserProxyTester {
    function functionReturningValue(bytes32 _someInputValue) returns(bytes32) {
        return _someInputValue;
    }

    function unsuccessfullFunction(bytes32) returns(bytes32) {
        revert();
    }

    function forward(address, bytes, uint, bool) returns(bytes32) {
        return 0x3432000000000000000000000000000000000000000000000000000000000000;
    }
}
