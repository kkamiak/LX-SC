pragma solidity ^0.4.11;

import './adapters/MultiEventsHistoryAdapter.sol';
import './adapters/Roles2LibraryAdapter.sol';
import './adapters/StorageAdapter.sol';
import './base/BitOps.sol';


/**
 * @title LaborX User Library.
 *
 * Skills:
 * Here we encode 128 different areas, each with 128 different categories
 * each with 256 different skills, using bit flags starting from the right,
 * for every user.
 * Areas and categories use odd bit flags to indicate that entity is
 * partially filled (area has categories, or category has skills).
 * Areas and categories use even bit flags to indicate that entity is
 * fully filled (area has all categories and skills, or category has all skills).
 * Skill can be repserented with any bit.
 * It results in following:
 *   all the areas for the user are defined using single uint256.
 *     all the categories of a single area of user are defined using single uint256.
 *       all the skills of a single category of user are defined using single uint256.
 *
 * 00000001 is the first partial area.
 * 00000100 is the second partial area.
 * 00000101 is the first and second partial areas.
 * 00001101 is the first partial and second full areas.
 * 00000010 is invalid, because in order to be full area also should be partial.
 * Same encoding is used for categories.
 *
 * For skills:
 * 00000001 is the first skill.
 * 00000010 is the second skill.
 * 01000011 is the first, second and seventh skill.
 *
 * Example skills structure for some user:
 * 00110001 - Partial first area, and full third area.
 *   01001101 - First area: partial first and fourth category, full second category.
 *     11100000 - First category: sixth, senventh and eighth skills.
 *     10001001 - Fourth category: first, fourth and eighth skills.
 */
contract UserLibrary is StorageAdapter, MultiEventsHistoryAdapter, Roles2LibraryAdapter, BitOps {
    StorageInterface.AddressUIntMapping skillAreas;
    StorageInterface.AddressUIntUIntMapping skillCategories;
    StorageInterface.AddressUIntUIntUIntMapping skills;

    event SkillAreasSet(address indexed self, address indexed user, uint areas);
    event SkillCategoriesSet(address indexed self, address indexed user, uint area, uint categories);
    event SkillsSet(address indexed self, address indexed user, uint area, uint category, uint skills);

    function UserLibrary(Storage _store, bytes32 _crate, address _roles2Library)
        StorageAdapter(_store, _crate)
        Roles2LibraryAdapter(_roles2Library)
    {
        skillAreas.init('skillAreas');
        skillCategories.init('skillCategories');
        skills.init('skills');
    }

    function setupEventsHistory(address _eventsHistory) auth() returns(bool) {
        if (getEventsHistory() != 0x0) {
            return false;
        }
        _setEventsHistory(_eventsHistory);
        return true;
    }

    function getAreaInfo(address _user, uint _area)
        singleOddFlag(_area)
        constant
    returns(bool partialArea, bool fullArea) {
        uint areas = store.get(skillAreas, _user);
        return (_hasFlag(areas, _area), _hasFlag(areas, _area << 1));
    }

    function hasArea(address _user, uint _area) constant returns(bool) {
        var (partial,) = getAreaInfo(_user, _area);
        return partial;
    }

    function getCategoryInfo(address _user, uint _area, uint _category)
        singleOddFlag(_category)
        constant
    returns(bool partialCategory, bool fullCategory) {
        var (partialArea, fullArea) = getAreaInfo(_user, _area);
        if (!partialArea) {
            return (false, false);
        }
        if (fullArea) {
            return (true, true);
        }
        uint categories = store.get(skillCategories, _user, _area);
        return (_hasFlag(categories, _category), _hasFlag(categories, _category << 1));
    }

    function hasCategory(address _user, uint _area, uint _category) constant returns(bool) {
        var (partial,) = getCategoryInfo(_user, _area, _category);
        return partial;
    }

    function hasSkill(address _user, uint _area, uint _category, uint _skill) singleFlag(_skill) constant returns(bool) {
        return hasSkills(_user, _area, _category, _skill);
    }

    function hasSkills(address _user, uint _area, uint _category, uint _skills) constant returns(bool) {
        var (partialCategory, fullCategory) = getCategoryInfo(_user, _area, _category);
        if (!partialCategory) {
            return false;
        }
        if (fullCategory) {
            return true;
        }
        uint userSkills = store.get(skills, _user, _area, _category);
        return _hasFlags(userSkills, _skills);
    }

    uint[] tempCategories;
    uint[] tempSkills;
    // If some area of category is full, then we are not looking into it cause observer can safely
    // assume that everything inside is filled.
    function getUserSkills(address _user) constant returns(uint, uint[], uint[]) {
        tempCategories.length = 0;
        tempSkills.length = 0;
        uint areas = store.get(skillAreas, _user);
        for (uint area = 1; area != 0; area = area << 2) {
            if (_isFullOrNull(areas, area)) {
                continue;
            }
            tempCategories.push(store.get(skillCategories, _user, area));
            for (uint category = 1; category != 0; category = category << 2) {
                if (_isFullOrNull(tempCategories[tempCategories.length - 1], category)) {
                    continue;
                }
                tempSkills.push(store.get(skills, _user, area, category));
            }
        }
        return (areas, tempCategories, tempSkills);
    }

    function setAreas(address _user, uint _areas)
        ifEvenThenOddTooFlags(_areas)
        auth()
    returns(bool) {
        for (uint area = 1; area != 0; area = area << 2) {
            if (_isFullOrNull(_areas, area)) {
                continue;
            }
            if (store.get(skillCategories, _user, area) == 0) {
                return false;
            }
        }
        _setAreas(_user, _areas);
        return true;
    }

    function setCategories(address _user, uint _area, uint _categories)
        singleOddFlag(_area)
        ifEvenThenOddTooFlags(_categories)
        hasFlags(_categories)
        auth()
    returns(bool) {
        _addArea(_user, _area);
        for (uint category = 1; category != 0; category = category << 2) {
            if (_isFullOrNull(_categories, category)) {
                continue;
            }
            if (store.get(skills, _user, _area, category) == 0) {
                return false;
            }
        }
        _setCategories(_user, _area, _categories);
        return true;
    }

    function setSkills(address _user, uint _area, uint _category, uint _skills)
        singleOddFlag(_area)
        singleOddFlag(_category)
        hasFlags(_skills)
        auth()
    returns(bool) {
        _addArea(_user, _area);
        _addCategory(_user, _area, _category);
        _setSkills(_user, _area, _category, _skills);
        return true;
    }

    function addMany(address _user, uint _areas, uint[] _categories, uint[] _skills) auth() public returns(bool) {
        return _setMany(_user, _areas, _categories, _skills, false);
    }

    function setMany(address _user, uint _areas, uint[] _categories, uint[] _skills) auth() returns(bool) {
        return _setMany(_user, _areas, _categories, _skills, true);
    }

    function _setMany(address _user, uint _areas, uint[] _categories, uint[] _skills, bool _overwrite)
        internal
    returns(bool) {
        uint categoriesCounter = 0;
        uint skillsCounter = 0;
        if (!_ifEvenThenOddTooFlags(_areas)) {
            return false;
        }
        _setAreas(_user, _overwrite ? _areas : (store.get(skillAreas, _user) | _areas));
        for (uint area = 1; area != 0; area = area << 2) {
            if (_isFullOrNull(_areas, area)) {
                // Nothing should be put inside full or empty area.
                continue;
            }

            require(_ifEvenThenOddTooFlags(_categories[categoriesCounter]));
            require(_categories[categoriesCounter] != 0);

            // Set categories for current partial area.
            _setCategories(_user, area, _overwrite ? _categories[categoriesCounter] : (store.get(skillCategories, _user, area) | _categories[categoriesCounter]));
            for (uint category = 1; category != 0; category = category << 2) {
                if (_isFullOrNull(_categories[categoriesCounter], category)) {
                    // Nothing should be put inside full or empty category.
                    continue;
                }
                require(_skills[skillsCounter] != 0);
                // Set skills for current partial category.
                _setSkills(_user, area, category, _skills[skillsCounter]);
                // Move to next skills.
                skillsCounter += 1;
            }
            // Move to next categories.
            categoriesCounter += 1;
        }
        return true;
    }


    function _addArea(address _user, uint _area) internal {
        if (hasArea(_user, _area)) {
            return;
        }
        _setAreas(_user, store.get(skillAreas, _user) | _area);
    }

    function _addCategory(address _user, uint _area, uint _category) internal {
        if (hasCategory(_user, _area, _category)) {
            return;
        }
        _setCategories(_user, _area, store.get(skillCategories, _user, _area) | _category);
    }

    function _setAreas(address _user, uint _areas) internal {
        store.set(skillAreas, _user, _areas);
        _emitSkillAreasSet(_user, _areas);
    }

    function _setCategories(address _user, uint _area, uint _categories) internal {
        store.set(skillCategories, _user, _area, _categories);
        _emitSkillCategoriesSet(_user, _area, _categories);
    }

    function _setSkills(address _user, uint _area, uint _category, uint _skills) internal {
        store.set(skills, _user, _area, _category, _skills);
        _emitSkillsSet(_user, _area, _category, _skills);
    }

    function _emitSkillAreasSet(address _user, uint _areas) internal {
        UserLibrary(getEventsHistory()).emitSkillAreasSet(_user, _areas);
    }

    function _emitSkillCategoriesSet(address _user, uint _area, uint _categories) internal {
        UserLibrary(getEventsHistory()).emitSkillCategoriesSet(_user, _area, _categories);
    }

    function _emitSkillsSet(address _user, uint _area, uint _category, uint _skills) internal {
        UserLibrary(getEventsHistory()).emitSkillsSet(_user, _area, _category, _skills);
    }

    function emitSkillAreasSet(address _user, uint _areas) {
        SkillAreasSet(_self(), _user, _areas);
    }

    function emitSkillCategoriesSet(address _user, uint _area, uint _categories) {
        SkillCategoriesSet(_self(), _user, _area, _categories);
    }

    function emitSkillsSet(address _user, uint _area, uint _category, uint _skills) {
        SkillsSet(_self(), _user, _area, _category, _skills);
    }

}
