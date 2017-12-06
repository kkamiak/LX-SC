pragma solidity ^0.4.11;

import './User.sol';
import './UserLibrary.sol';
import './UserProxy.sol';
import './adapters/MultiEventsHistoryAdapter.sol';
import './adapters/Roles2LibraryAdapter.sol';


contract UserLibraryInterface {
    function setMany(address _user, uint _areas, uint[] _categories, uint[] _skills) public returns(bool);
}


contract UserFactory is MultiEventsHistoryAdapter, Roles2LibraryAdapter {
    UserLibraryInterface userLibrary;

    event UserCreated(
        address indexed self,
        address indexed user,
        address proxy,
        address recoveryContract,
        address owner,
        uint8[] roles,
        uint areas,
        uint[] categories,
        uint[] skills
    );

    function UserFactory(address _roles2Library) Roles2LibraryAdapter(_roles2Library) public {}

    function setupEventsHistory(address _eventsHistory) public auth() returns(bool) {
        if (getEventsHistory() != 0x0) {
            return false;
        }
        _setEventsHistory(_eventsHistory);
        return true;
    }

    function setUserLibrary(UserLibraryInterface _userLibrary) public auth() returns(bool) {
        userLibrary = _userLibrary;
        return true;
    }

    function getUserLibrary() public constant returns(address) {
        return userLibrary;
    }


    function createUserWithProxyAndRecovery(
        address _owner,
        address _recoveryContract,
        uint8[] _roles,
        uint _areas,
        uint[] _categories,
        uint[] _skills
    )
        public
        auth()
    returns(bool) {
        User user = new User(_owner, _recoveryContract);
        UserProxy proxy = UserProxy(user.getUserProxy());

        if(!_setRoles(proxy, _roles)) {
            revert();
        }

        if(!_setSkills(proxy, _areas, _categories, _skills)) {
            revert();
        }

        _emitUserCreated(user, proxy, _recoveryContract, _owner, _roles, _areas, _categories, _skills);
    }

    function _setRoles(address _user, uint8[] _roles) internal returns(bool) {
        for (uint i = 0; i < _roles.length; i++) {
            if (!roles2Library.addUserRole(_user, _roles[i])) {
                return false;
            }
        }
        return true;
    }

    function _setSkills(address _user, uint _areas, uint[] _categories, uint[] _skills)
        internal
    returns(bool) {
        if (_areas == 0) {
            return true;
        }
        if (!userLibrary.setMany(_user, _areas, _categories, _skills)) {
            return false;
        }
        return true;
    }

    function _emitUserCreated(
        address _user,
        address _proxy,
        address _recoveryContract,
        address _owner,
        uint8[] _roles,
        uint _areas,
        uint[] _categories,
        uint[] _skills
    ) internal {
        UserFactory(getEventsHistory()).emitUserCreated(
            _user,
            _proxy,
            _recoveryContract,
            _owner,
            _roles,
            _areas,
            _categories,
            _skills
        );
    }

    function emitUserCreated(
        address _user,
        address _proxy,
        address _recoveryContract,
        address _owner,
        uint8[] _roles,
        uint _areas,
        uint[] _categories,
        uint[] _skills
    ) public {
        UserCreated(
            _self(),
            _user,
            _proxy,
            _recoveryContract,
            _owner,
            _roles,
            _areas,
            _categories,
            _skills
        );
    }
}
