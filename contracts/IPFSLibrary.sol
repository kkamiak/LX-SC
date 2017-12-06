pragma solidity ^0.4.11;

import './adapters/MultiEventsHistoryAdapter.sol';
import './adapters/Roles2LibraryAdapter.sol';
import './adapters/StorageAdapter.sol';


contract IPFSLibrary is StorageAdapter, MultiEventsHistoryAdapter, Roles2LibraryAdapter {
    StorageInterface.AddressBytes32Bytes32Mapping ipfsHashes;

    event HashSet(address indexed self, address indexed setter, bytes32 indexed key, bytes32 hash);

    function IPFSLibrary(Storage _store, bytes32 _crate, address _roles2Library)
        public
        StorageAdapter(_store, _crate)
        Roles2LibraryAdapter(_roles2Library)
    {
        ipfsHashes.init('ipfsHashes');
    }

    function setupEventsHistory(address _eventsHistory) external auth() returns(bool) {
        if (getEventsHistory() != 0x0) {
            return false;
        }
        _setEventsHistory(_eventsHistory);
        return true;
    }

    function getHash(address _from, bytes32 _itemName) public view returns(bytes32) {
        return store.get(ipfsHashes, _from, _itemName);
    }

    function setHash(bytes32 _itemName, bytes32 _itemHash) public returns(bool) {
        store.set(ipfsHashes, msg.sender, _itemName, _itemHash);
        _emitHashSet(msg.sender, _itemName, _itemHash);
        return true;
    }

    function _emitHashSet(address _from, bytes32 _itemName, bytes32 _itemHash) internal {
        IPFSLibrary(getEventsHistory()).emitHashSet(_from, _itemName, _itemHash);
    }

    function emitHashSet(address _from, bytes32 _itemName, bytes32 _itemHash) public {
        HashSet(_self(), _from, _itemName, _itemHash);
    }
}
