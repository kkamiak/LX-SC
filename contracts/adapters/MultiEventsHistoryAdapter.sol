pragma solidity ^0.4.11;

/**
 * @title General MultiEventsHistory user.
 *
 */
contract MultiEventsHistoryAdapter {
    address eventsHistory;

    event Error(address indexed self, bytes32 msg);

    function getEventsHistory() public constant returns(address) {
        return eventsHistory;
    }

    function _setEventsHistory(address _eventsHistory) internal returns (bool) {
        eventsHistory = _eventsHistory;
        return true;
    }

    // It is address of MultiEventsHistory caller assuming we are inside of delegate call.
    function _self() view internal returns(address) {
        return msg.sender;
    }

    function _emitError(bytes32 _msg) internal {
        MultiEventsHistoryAdapter(getEventsHistory()).emitError(_msg);
    }

    function emitError(bytes32 _msg) public {
        Error(_self(), _msg);
    }
}
