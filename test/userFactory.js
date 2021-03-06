"use strict";

const Mock = artifacts.require('./Mock.sol');
const MultiEventsHistory = artifacts.require('./MultiEventsHistory.sol');
const Roles2Library = artifacts.require('./Roles2Library.sol');
const Roles2LibraryInterface = artifacts.require('./Roles2LibraryInterface.sol');
const User = artifacts.require('./User.sol');
const UserFactory = artifacts.require('./UserFactory.sol');
const UserProxy = artifacts.require('./UserProxy.sol');

const Asserts = require('./helpers/asserts');
const Reverter = require('./helpers/reverter');
const Promise = require('bluebird');
const helpers = require('./helpers/helpers');


contract('UserFactory', function(accounts) {
  const reverter = new Reverter(web3);
  afterEach('revert', reverter.revert);

  const asserts = Asserts(assert);
  const recovery = "0xffffffffffffffffffffffffffffffffffffffff";
  const roles2LibraryInterface = web3.eth.contract(Roles2LibraryInterface.abi).at('0x0');
  let mock;
  let multiEventsHistory;
  let roles2Library;
  let userFactory;

  before('setup', () => {
    return Mock.deployed()
    .then(instance => mock = instance)
    .then(() => helpers.ignoreAuth(mock))
    .then(() => Roles2Library.deployed())
    .then(instance => roles2Library = instance)
    .then(() => MultiEventsHistory.deployed())
    .then(instance => multiEventsHistory = instance)
    .then(() => UserFactory.deployed())
    .then(instance => userFactory = instance)
    .then(() => multiEventsHistory.authorize(userFactory.address))
    .then(() => userFactory.setupEventsHistory(multiEventsHistory.address))
    .then(() => userFactory.setUserLibrary(mock.address))
    .then(reverter.snapshot);
  });

  describe("Contract setup", () => {

    it('should check auth on setup event history', () => {
      const caller = accounts[1];
      const newAddress = '0xffffffffffffffffffffffffffffffffffffffff';
      return Promise.resolve()
        .then(() => helpers.ignoreAuth(mock, false))
        .then(() => mock.expect(
          userFactory.address,
          0,
          roles2LibraryInterface.canCall.getData(
            caller,
            userFactory.address,
            userFactory.contract.setupEventsHistory.getData().slice(0, 10)
          ), 0)
        )
        .then(() => userFactory.setupEventsHistory(newAddress, {from: caller}))
        .then(helpers.assertExpectations(mock));
    });

    it('should check auth on setup user library', () => {
      const caller = accounts[1];
      const newAddress = '0xffffffffffffffffffffffffffffffffffffffff';
      return Promise.resolve()
        .then(() => helpers.ignoreAuth(mock, false))
        .then(() => mock.expect(
          userFactory.address,
          0,
          roles2LibraryInterface.canCall.getData(
            caller,
            userFactory.address,
            userFactory.contract.setUserLibrary.getData().slice(0, 10)
          ), 0)
        )
        .then(() => userFactory.setUserLibrary(newAddress, {from: caller}))
        .then(helpers.assertExpectations(mock));
    });

  });


  describe("User creation", () => {

    it('should check auth on user creation', () => {
      const caller = accounts[1];
      const owner = accounts[2];
      const roles = [1, 2];
      const areas = 333;
      const categories = [1, 2, 3];
      const skills = [4, 5, 6];
      const expectedSig = helpers.getSig(
        "createUserWithProxyAndRecovery(address,address,uint8[],uint256,uint256[],uint256[])"
      );
      return Promise.resolve()
        .then(() => helpers.ignoreAuth(mock, false))
        .then(() => mock.expect(
          userFactory.address,
          0,
          roles2LibraryInterface.canCall.getData(
            caller,
            userFactory.address,
            expectedSig
          ), 0)
        )
        .then(() => userFactory.createUserWithProxyAndRecovery(
          owner, recovery, roles, areas, categories, skills, {from: caller}
        ))
        .then(helpers.assertExpectations(mock));
    });

    it.skip('should THROW if failed to set roles', () => {
      const caller = accounts[1];
      const owner = accounts[2];
      const roles = [1, 2];
      const areas = 333;
      const categories = [1, 2, 3];
      const skills = [4, 5, 6];
      return Promise.resolve()
        .then(() => roles2Library.addUserSkill) // FIXME
        .then(() => userFactory.setRoles2Library(roles2Library.address))
        .then(() => asserts.throws(
          userFactory.createUserWithProxyAndRecovery(
            owner, recovery, roles, areas, categories, skills, {from: caller}
        )));
    });

    it('should THROW if failed to set skills'); // TODO

    it('should create users with roles', () => {
      const owner = accounts[1];
      const roles = [1, 2];
      const areas = 0;
      const categories = [];
      const skills = [];
      return userFactory.createUserWithProxyAndRecovery(
        owner, recovery, roles, areas, categories, skills
      )
        .then(result => {
          assert.equal(result.logs.length, 1);
          assert.equal(result.logs[0].address, multiEventsHistory.address);
          assert.equal(result.logs[0].args.self, userFactory.address);
          assert.equal(result.logs[0].event, 'UserCreated');
          assert.equal(result.logs[0].args.owner, owner);
          assert.equal(result.logs[0].args.roles.length, 2);
          assert.equal(result.logs[0].args.areas.toString(), '0');
          assert.equal(result.logs[0].args.categories.length, 0);
          assert.equal(result.logs[0].args.skills.length, 0);
          assert.equal(result.logs[0].args.recoveryContract, recovery);
          assert.notEqual(result.logs[0].args.user, undefined);
          assert.notEqual(result.logs[0].args.proxy, undefined);
        })
        .then(() => mock.callsCount())
        .then(asserts.equal(2));
    });

    it('should create users with skills', () => {
      const owner = accounts[1];
      const roles = [];
      const areas = 4;
      const categories = [1];
      const skills = [1];
      return userFactory.createUserWithProxyAndRecovery(
        owner, recovery, roles, areas, categories, skills
      )
        .then(result => {
          assert.equal(result.logs.length, 1);
          assert.equal(result.logs[0].address, multiEventsHistory.address);
          assert.equal(result.logs[0].args.self, userFactory.address);
          assert.equal(result.logs[0].event, 'UserCreated');
          assert.equal(result.logs[0].args.owner, owner);
          assert.equal(result.logs[0].args.roles.length, 0);
          assert.equal(result.logs[0].args.areas.toString(2), '100');
          assert.equal(result.logs[0].args.categories.length, 1);
          assert.equal(result.logs[0].args.skills.length, 1);
          assert.equal(result.logs[0].args.recoveryContract, recovery);
          assert.notEqual(result.logs[0].args.proxy, undefined);
          assert.notEqual(result.logs[0].args.user, undefined);
        })
        .then(() => mock.callsCount())
        .then(asserts.equal(1));
    });

    it('should create users with roles and skills', () => {
      const owner = accounts[1];
      const roles = [1, 2];
      const areas = 4;
      const categories = [1];
      const skills = [1];
      return userFactory.createUserWithProxyAndRecovery(
        owner, recovery, roles, areas, categories, skills
      )
        .then(result => {
          assert.equal(result.logs.length, 1);
          assert.equal(result.logs[0].address, multiEventsHistory.address);
          assert.equal(result.logs[0].args.self, userFactory.address);
          assert.equal(result.logs[0].event, 'UserCreated');
          assert.equal(result.logs[0].args.owner, owner);
          assert.equal(result.logs[0].args.roles.length, 2);
          assert.equal(result.logs[0].args.areas.toString(2), '100');
          assert.equal(result.logs[0].args.categories.length, 1);
          assert.equal(result.logs[0].args.skills.length, 1);
          assert.equal(result.logs[0].args.recoveryContract, recovery);
          assert.notEqual(result.logs[0].args.proxy, undefined);
          assert.notEqual(result.logs[0].args.user, undefined);
        })
        .then(() => mock.callsCount())
        .then(asserts.equal(3));
    });

    it('should create users without roles and skills', () => {
      const owner = accounts[1];
      return userFactory.createUserWithProxyAndRecovery(owner, recovery, [], 0, [], [])
        .then(result => {
          assert.equal(result.logs.length, 1);
          assert.equal(result.logs[0].event, 'UserCreated');
          assert.equal(result.logs[0].args.owner, owner);
          assert.equal(result.logs[0].args.roles.length, 0);
          assert.equal(result.logs[0].args.areas.toString(), '0');
          assert.equal(result.logs[0].args.categories.length, 0);
          assert.equal(result.logs[0].args.skills.length, 0);
          assert.equal(result.logs[0].args.recoveryContract, recovery);
          assert.notEqual(result.logs[0].args.proxy, undefined);
          assert.notEqual(result.logs[0].args.user, undefined);
        })
        .then(() => mock.callsCount())
        .then(asserts.equal(0));
    });

    it('should set correct ownerships on user creation', () => {
      const owner = accounts[1];
      let user;
      let proxy;
      return userFactory.createUserWithProxyAndRecovery(owner, recovery, [], 0, [], [])
        .then(tx => {
          user = web3.eth.contract(User.abi).at(tx.logs[0].args.user);
          proxy = web3.eth.contract(UserProxy.abi).at(tx.logs[0].args.proxy);
          return user.contractOwner();
        })
        .then(result => assert.equal(result, owner))
        .then(() => proxy.contractOwner())
        .then(result => assert.equal(result, user.address));
    });

    it('should create multiple users', () => {
      const users = accounts.slice(2, 5);
      const roles = [1, 2, 3, 4, 5];
      const areas = 0;
      const categories = [1, 2, 3, 4, 5];
      const skills = [1, 2, 3, 4, 5];
      return Promise.each(users, u => {
        return userFactory.createUserWithProxyAndRecovery(
            u, recovery, roles, areas, categories, skills
          )
          .then(helpers.assertLogs([{
            event: "UserCreated",
            args: {
              owner: u
            }
          }]))
      })
    });

    it('should create users with 250 roles', () => {
      const owner = accounts[1];
      const areas = 1;
      const categories = [1];
      const skills = [1];

      const roles = [...Array(251).keys()].slice(1);
      return userFactory.createUserWithProxyAndRecovery(
          owner, recovery, roles, areas, categories, skills
        )
        .then(helpers.assertLogs([{
          address: multiEventsHistory.address,
          event: "UserCreated",
          args: {
            owner: owner,
            roles: roles,
            areas: 1,
            categories: categories,
            skills: skills,
            recoveryContract: recovery
          }
        }]))
        .then(() => mock.callsCount())
        .then(asserts.equal(roles.length + 1)); // 250 roles + 1 skill
    });

    it('should create users with 250 categories', () => {
      const owner = accounts[1];
      const roles = [1];
      const areas = 1;
      const categories = [...Array(251).keys()].slice(1);
      const skills = [1];
      return userFactory.createUserWithProxyAndRecovery(
          owner, recovery, roles, areas, categories, skills
        )
        .then(helpers.assertLogs([{
          address: multiEventsHistory.address,
          event: "UserCreated",
          args: {
            owner: owner,
            roles: roles,
            areas: 1,
            categories: categories,
            skills: skills,
            recoveryContract: recovery
          }
        }]))
        .then(() => mock.callsCount())
        .then(asserts.equal(2));
    });

    it('should create users with 250 skills', () => {
      const owner = accounts[1];
      const roles = [1];
      const areas = 1;
      const categories = [1];
      const skills = [...Array(251).keys()].slice(1);
      return userFactory.createUserWithProxyAndRecovery(
          owner, recovery, roles, areas, categories, skills
        )
        .then(helpers.assertLogs([{
          address: multiEventsHistory.address,
          event: "UserCreated",
          args: {
            owner: owner,
            roles: roles,
            areas: 1,
            categories: categories,
            skills: skills,
            recoveryContract: recovery
          }
        }]))
        .then(() => mock.callsCount())
        .then(asserts.equal(2));
    });

  });

});
