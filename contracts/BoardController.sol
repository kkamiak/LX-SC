pragma solidity ^0.4.11;

import './adapters/MultiEventsHistoryAdapter.sol';
import './adapters/Roles2LibraryAndERC20LibraryAdapter.sol';
import './adapters/StorageAdapter.sol';
import './base/BitOps.sol';

contract BoardController is StorageAdapter, MultiEventsHistoryAdapter, Roles2LibraryAndERC20LibraryAdapter, BitOps {
    StorageInterface.UInt boardsCount;

    StorageInterface.UIntAddressMapping boardCreator;
    StorageInterface.UIntBytes32Mapping boardDescription;
    StorageInterface.UIntBytes32Mapping boardName;

    StorageInterface.UIntUIntMapping boardTagsArea;
    StorageInterface.UIntUIntMapping boardTagsCategory;
    StorageInterface.UIntUIntMapping boardTags;

    StorageInterface.UIntBoolMapping boardStatus;
    StorageInterface.UIntUIntBoolMapping jobBinding;
    StorageInterface.UIntUIntMapping jobsBoard;
    StorageInterface.UintAddressBoolMapping userBinding;

    event BoardCreated(
        address indexed self,
        uint indexed boardId,
        bytes32 name,
        bytes32 boardDescription,
        address creator,
        uint boardTags,
        uint boardTagsArea,
        uint boardTagsCategory,
        bool status
    );

    event JobBinded(address indexed self, uint indexed boardId, uint jobId, bool status);
    event UserBinded(address indexed self, uint indexed boardId, address user, bool status);
    event BoardClosed(address indexed self, uint indexed boardId, bool status);

    modifier notBindedJobYet(uint _boardId, uint _jobId) {
      if (store.get(jobBinding, _boardId, _jobId) == true) {
        return;
      }
      _;
    }

    modifier notBindedUserYet(uint _boardId, address _user) {
      if (store.get(userBinding, _boardId, _user) == true) {
        return;
      }
      _;
    }

    modifier notClosed(uint _baordId) {
      if (store.get(boardStatus, _baordId) == false) {
        return;
      }
      _;
    }

    function BoardController(Storage _store, bytes32 _crate, address _roles2Library, address _erc20Library)
      public
      StorageAdapter(_store, _crate)
      Roles2LibraryAndERC20LibraryAdapter(_roles2Library, _erc20Library)
    {
        boardsCount.init('boardsCount');

        boardDescription.init('boardDescription');
        boardCreator.init('boardCreator');
        boardName.init('boardName');

        boardTagsArea.init('boardTagsArea');
        boardTagsCategory.init('boardTagsCategory');
        boardTags.init('boardTags');

        jobBinding.init('jobBinding');
        jobsBoard.init('jobsBoard');
        userBinding.init('userBinding');
        boardStatus.init('boardStatus');
    }

    function setupEventsHistory(address _eventsHistory) public auth() returns(bool) {
        if (getEventsHistory() != 0x0) {
            return false;
        }
        _setEventsHistory(_eventsHistory);
        return true;
    }

    function createBoard(bytes32 _name, bytes32 _boardDescription, uint _tags, uint _tagsArea, uint _tagsCategory)
        external
        auth()
        singleOddFlag(_tagsArea)
        singleOddFlag(_tagsCategory)
        hasFlags(_tags)
    returns(uint) {
        uint boardId = store.get(boardsCount) + 1;
        store.set(boardsCount, boardId);
        store.set(boardName, boardId, _name);
        store.set(boardCreator, boardId, msg.sender);
        store.set(boardTagsArea, boardId, _tagsArea);
        store.set(boardTagsCategory, boardId, _tagsCategory);
        store.set(boardTags, boardId, _tags);
        store.set(boardStatus, boardId, true);
        store.set(boardDescription, boardId, _boardDescription);
        _emitBoardCreated(boardId, _name, _boardDescription, msg.sender, _tags, _tagsArea, _tagsCategory, true);
        return boardId;
    }

    function bindJobWithBoard(uint _boardId, uint _jobId)
        public
        notBindedJobYet(_boardId, _jobId)
        notClosed(_boardId)
    returns(bool) {
        store.set(jobsBoard, _jobId, _boardId);
        store.set(jobBinding, _boardId, _jobId, true);
        _emitJobBinded( _boardId, _jobId, true);
    }

    function bindUserWithBoard(uint _boardId, address _user)
        public
        notBindedUserYet(_boardId, _user)
        notClosed(_boardId)
    returns(bool) {
        store.set(userBinding, _boardId, _user, true);
        _emitUserBinded( _boardId, _user, true);
    }

    function closeBoard(uint _boardId)
        external
        auth()
        notClosed(_boardId)
    returns(bool) {
        store.set(boardStatus, _boardId, false);
        _emitBoardClosed( _boardId, false);
    }

    function _emitBoardCreated(
        uint _boardId,
        bytes32 _name,
        bytes32 _boardDescription,
        address _creator,
        uint _tags,
        uint _tagsArea,
        uint _tagsCategory,
        bool _boardStatus
    ) internal {
        BoardController(getEventsHistory()).emitBoardCreated(
          _boardId,
          _name,
          _boardDescription,
          _creator,
          _tags,
          _tagsArea,
          _tagsCategory,
          _boardStatus
        );
    }

    function _emitJobBinded(uint _boardId, uint _jobId, bool _status) internal {
        BoardController(getEventsHistory()).emitJobBinded(_boardId, _jobId, _status);
    }

    function _emitUserBinded(uint _boardId, address _user, bool _status) internal {
        BoardController(getEventsHistory()).emitUserBinded(_boardId, _user, _status);
    }

    function _emitBoardClosed(uint _boardId, bool _status) internal {
        BoardController(getEventsHistory()).emitBoardClosed(_boardId, _status);
    }

    function emitBoardCreated(
        uint _boardId,
        bytes32 _name,
        bytes32 _boardDescription,
        address _creator,
        uint _tags,
        uint _tagsArea,
        uint _tagsCategory,
        bool _boardStatus
    )
        public
    {
        BoardCreated(
          _self(),
          _boardId,
          _name,
          _boardDescription,
          _creator,
          _tags,
          _tagsArea,
          _tagsCategory,
          _boardStatus
          );
    }

    function emitJobBinded(uint _boardId, uint _jobId, bool _status) public {
      JobBinded(_self(), _boardId, _jobId, _status);
    }

    function emitUserBinded(uint _boardId, address _user, bool _status) public {
      UserBinded(_self(), _boardId, _user, _status);
    }

    function emitBoardClosed(uint _boardId, bool _status) public {
      BoardClosed(_self(), _boardId, _status);
    }

    function getBoardsCount() public view returns(uint) {
        return store.get(boardsCount);
    }

    function getBoardStatus(uint _boardId) public view returns(bool) {
        return store.get(boardStatus, _boardId);
    }

    function getJobStatus(uint _boardId, uint _jobId) public view returns(bool) {
        return store.get(jobBinding, _boardId, _jobId);
    }

    function getUserStatus(uint _boardId, address _user) public view returns(bool) {
        return store.get(userBinding, _boardId, _user);
    }

    function getJobsBoard(uint _jobId) public view returns(uint) {
        return store.get(jobsBoard, _jobId);
    }

}
