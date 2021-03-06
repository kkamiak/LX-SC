"use strict";

const BalanceHolder = artifacts.require('./BalanceHolder.sol');
const ERC20Library = artifacts.require('./ERC20Library.sol');
const FakeCoin = artifacts.require('./FakeCoin.sol');
const JobController = artifacts.require('./JobController.sol');
const ManagerMock = artifacts.require('./ManagerMock.sol');
const Mock = artifacts.require('./Mock.sol');
const MultiEventsHistory = artifacts.require('./MultiEventsHistory.sol');
const PaymentGateway = artifacts.require('./PaymentGateway.sol');
const PaymentProcessor = artifacts.require('./PaymentProcessor.sol');
const Roles2LibraryInterface = artifacts.require('./Roles2LibraryInterface.sol');
const Storage = artifacts.require('./Storage.sol');
const UserLibrary = artifacts.require('./UserLibrary.sol');
const BoardController = artifacts.require('./BoardController.sol');
const Roles2Library = artifacts.require('./Roles2Library.sol');

const Asserts = require('./helpers/asserts');
const Promise = require('bluebird');
const Reverter = require('./helpers/reverter');

const helpers = require('./helpers/helpers');


contract('BoardController', function(accounts) {
  const reverter = new Reverter(web3);
  afterEach('revert', reverter.revert);

  const asserts = Asserts(assert);
  const roles2LibraryInterface = web3.eth.contract(Roles2LibraryInterface.abi).at('0x0');
  const userLibraryInterface = web3.eth.contract(UserLibrary.abi).at('0x0');

  const assertInternalBalance = (address, coinAddress, expectedValue) => {
    return (actualValue) => {
      return paymentGateway.getBalance(address, coinAddress)
      .then(asserts.equal(expectedValue));
    };
  };

  const assertExternalBalance = (address, coinAddress, expectedValue) => {
    return (actualValue) => {
      return paymentGateway.getBalanceOf(address, coinAddress)
      .then(asserts.equal(expectedValue));
    };
  };

  const assertExpectations = (expected = 0, callsCount = null) => {
    let expectationsCount;
    return () => {
      return mock.expectationsLeft()
      .then(asserts.equal(expected))
      .then(() => mock.expectationsCount())
      .then(result => expectationsCount = result)
      .then(() => mock.callsCount())
      .then(result => asserts.equal(callsCount === null ? expectationsCount : callsCount)(result));
    };
  };

  const ignoreAuth = (enabled = true) => {
    return mock.ignore(roles2LibraryInterface.canCall.getData().slice(0, 10), enabled);
  };

  const ignoreSkillsCheck = (enabled = true) => {
    return mock.ignore(userLibraryInterface.hasSkills.getData().slice(0, 10), enabled);
  }

  let fakeCoin;
  let storage;
  let boardController;
  let jobController;
  let multiEventsHistory;
  let paymentProcessor;
  let erc20Library;
  let userLibrary;
  let paymentGateway;
  let balanceHolder;
  let roles2Library;
  let mock;

  const root = accounts[5];
  const moderator = accounts[6];
  const moderator2 = accounts[7];
  const stranger = accounts[9];
  const client = accounts[1];
  const role = 255;
  const createBoard = helpers.getSig("createBoard(address,uint8)");
  const closeBoard = helpers.getSig("closeBoard(address,uint8)");
  const boardId = 1;
  const boardName = 'Name';
  const boardDescription = 'Description';
  const boardTags = 1;
  const boardTagsArea = 1;
  const boardTagsCategory = 1;
  const jobId = 1;
  const jobArea = 4;
  const jobCategory = 4;
  const jobSkills = 4;
  const jobDetails = 'Job details';

  before('setup', () => {
    return Mock.deployed()
    .then(instance => mock = instance)
    .then(() => ignoreAuth())
    .then(() => ignoreSkillsCheck())
    .then(() => FakeCoin.deployed())
    .then(instance => fakeCoin = instance)
    .then(() => MultiEventsHistory.deployed())
    .then(instance => multiEventsHistory = instance)
    .then(() => Storage.deployed())
    .then(instance => storage = instance)
    .then(() => ManagerMock.deployed())
    .then(instance => storage.setManager(instance.address))
    .then(() => BalanceHolder.deployed())
    .then(instance => balanceHolder = instance)
    .then(() => ERC20Library.deployed())
    .then(instance => erc20Library = instance)
    .then(() => UserLibrary.deployed())
    .then(instance => userLibrary = instance)
    .then(() => Roles2Library.deployed())
    .then(instance => roles2Library = instance)
    .then(() => PaymentGateway.deployed())
    .then(instance => paymentGateway = instance)
    .then(() => PaymentProcessor.deployed())
    .then(instance => paymentProcessor = instance)
    .then(() => JobController.deployed())
    .then(instance => jobController = instance)
    .then(() => BoardController.deployed())
    .then(instance => boardController = instance)

    .then(() => multiEventsHistory.authorize(boardController.address))
    .then(() => multiEventsHistory.authorize(erc20Library.address))
    .then(() => multiEventsHistory.authorize(userLibrary.address))
    .then(() => multiEventsHistory.authorize(paymentGateway.address))
    .then(() => multiEventsHistory.authorize(jobController.address))
    .then(() => multiEventsHistory.authorize(roles2Library.address))

    .then(() => roles2Library.setupEventsHistory(multiEventsHistory.address))

    .then(() => erc20Library.setupEventsHistory(multiEventsHistory.address))
    .then(() => erc20Library.addContract(fakeCoin.address))

    .then(() => userLibrary.setupEventsHistory(multiEventsHistory.address))

    .then(() => paymentGateway.setupEventsHistory(multiEventsHistory.address))
    .then(() => paymentGateway.setBalanceHolder(balanceHolder.address))

    .then(() => paymentProcessor.setPaymentGateway(paymentGateway.address))

    .then(() => jobController.setupEventsHistory(multiEventsHistory.address))
    .then(() => jobController.setPaymentProcessor(paymentProcessor.address))
    .then(() => jobController.setUserLibrary(mock.address))

    .then(() => boardController.setupEventsHistory(multiEventsHistory.address))

    .then(() => fakeCoin.mint(client, '0xfffffffffffffffffff'))
    .then(() => paymentGateway.deposit('0xfffffffffffffffffff', fakeCoin.address, {from: client}))

    .then(() => roles2Library.setRootUser(root, true))
    .then(() => roles2Library.addRoleCapability(role, roles2Library.address, createBoard, {from: root}))
    .then(() => roles2Library.addUserRole(moderator, role, {from: root}))

    .then(reverter.snapshot);
  });


  describe('Board creating', () => {

    it('should allow to create a board by moderator', () => {
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.getBoardsCount())
        .then(asserts.equal(1));
    });

    it('should allow to create a board by root', () => {
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: root}))
        .then(() => boardController.getBoardsCount())
        .then(asserts.equal(1));
    });

    it('should allow to create a board several times by different moderators', () => {
      return Promise.resolve()
        .then(() => roles2Library.addUserRole(moderator2, role, {from: root}))
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.createBoard('Name2', boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator2}))
        .then(() => boardController.getBoardsCount())
        .then(asserts.equal(2));
    });

    it('should allow to create a board several times by root and moderator', () => {
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.createBoard('Name2', boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: root}))
        .then(() => boardController.getBoardsCount())
        .then(asserts.equal(2));
    });

    it.skip('should NOT allow to create a board by strangers', () => {
      return Promise.resolve()
        .then(() => boardController.createBoard.call(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: stranger}))
        .then(asserts.equal(0));
    });

    it.skip('should NOT allow to create a board with negative tags', () => {
      const negativeTags = -1;
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, negativeTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.getBoardsCount())
        .then(asserts.equal(0));
    });

    it('should NOT allow to create a board with negative area', () => {
      const negativeArea = -1;
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, negativeArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.getBoardsCount())
        .then(asserts.equal(0));
    });

    it('should NOT allow to create a board with negative category', () => {
      const negativeCategory = -1;
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, negativeCategory, {from: moderator}))
        .then(() => boardController.getBoardsCount())
        .then(asserts.equal(0));
    });

    it('should NOT allow to create a board without tags', () => {
      const zeroTag = 0;
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, zeroTag, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.getBoardsCount())
        .then(asserts.equal(0));
    });

    it('should allow to create a board after failed trying', () => {
      const zeroTag = 0;
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, zeroTag, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.getBoardsCount())
        .then(asserts.equal(1));
    });

    it('should emit "BoardCreated" event', () => {
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(tx => {
          assert.equal(tx.logs.length, 1);
          assert.equal(tx.logs[0].address, multiEventsHistory.address);
          assert.equal(tx.logs[0].event, 'BoardCreated');
          const log = tx.logs[0].args;
          assert.equal(log.self, boardController.address);
          assert.equal(log.boardId.toString(), '1');
          assert.equal(log.boardTags.toString(), boardTags);
          assert.equal(log.boardTagsArea.toString(), boardTagsArea);
          assert.equal(log.boardTagsCategory.toString(), boardTagsCategory);
        })
    });

  });

  describe('Job binding', () => {

    it('should allow to bind job on board', () => {
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => jobController.postJob(jobArea, jobCategory, jobSkills, jobDetails, {from: client}))
        .then(() => boardController.bindJobWithBoard(boardId, jobId))
        .then(() => boardController.getJobStatus(boardId, jobId))
        .then(asserts.equal(true));
    });

    it('should NOT allow to bind job on closed board', () => {
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => jobController.postJob(jobArea, jobCategory, jobSkills, jobDetails, {from: client}))
        .then(() => boardController.closeBoard(boardId, {from: moderator}))
        .then(() => boardController.bindJobWithBoard.call(boardId, jobId))
        .then(assert.isFalse);
    });

    it('should NOT allow to bind binded job on other board', () => {
      const boardId2 = 2;
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.createBoard('Name2', boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => jobController.postJob(jobArea, jobCategory, jobSkills, jobDetails, {from: client}))
        .then(() => boardController.bindJobWithBoard(jobId, boardId))
        .then(() => boardController.bindJobWithBoard.call(jobId, boardId2))
        .then(assert.isFalse);
    });

    it('should NOT allow to bind binded job on same board twice', () => {
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => jobController.postJob(jobArea, jobCategory, jobSkills, jobDetails, {from: client}))
        .then(() => boardController.bindJobWithBoard(jobId, boardId))
        .then(() => boardController.bindJobWithBoard.call(jobId, boardId))
        .then(assert.isFalse);
    });

    it('should emit "Job Binded" event', () => {
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => jobController.postJob(jobArea, jobCategory, jobSkills, jobDetails, {from: client}))
        .then(() => boardController.bindJobWithBoard(boardId, jobId))
        .then(tx => {
          assert.equal(tx.logs.length, 1);
          assert.equal(tx.logs[0].address, multiEventsHistory.address);
          assert.equal(tx.logs[0].event, 'JobBinded');
          const log = tx.logs[0].args;
          assert.equal(log.self, boardController.address);
          assert.equal(log.jobId.toString(), '1');
          assert.equal(log.boardId.toString(), '1');
          assert.equal(log.status, true);
        })
    });

  });

  describe('User binding', () => {

    it('should allow to bind user on board', () => {
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.bindUserWithBoard(boardId, client))
        .then(() => boardController.getUserStatus(boardId, client))
        .then(asserts.equal(true));
    });

    it('should allow to bind user not only on one board', () => {
      const boardId2 = 2;
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.createBoard('Name2', boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.bindUserWithBoard(boardId, client))
        .then(() => boardController.bindUserWithBoard(boardId2, client))
        .then(() => boardController.getUserStatus(boardId, client))
        .then(asserts.equal(true))
        .then(() => boardController.getUserStatus(boardId2, client))
        .then(asserts.equal(true));
    });

    it('should NOT allow to bind user on closed board', () => {
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.closeBoard(boardId, {from: moderator}))
        .then(() => boardController.bindUserWithBoard.call(boardId, client))
        .then(assert.isFalse);
    });

    it('should NOT allow to bind binded user on same board twice', () => {
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.bindUserWithBoard(boardId, client))
        .then(() => boardController.bindUserWithBoard.call(boardId, client))
        .then(assert.isFalse);
    });

    it('should emit "User Binded" event', () => {
      return Promise.resolve()
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.bindUserWithBoard(boardId, client))
        .then(tx => {
          assert.equal(tx.logs.length, 1);
          assert.equal(tx.logs[0].address, multiEventsHistory.address);
          assert.equal(tx.logs[0].event, 'UserBinded');
          const log = tx.logs[0].args;
          assert.equal(log.self, boardController.address);
          assert.equal(log.user.toString(), client);
          assert.equal(log.boardId.toString(), '1');
          assert.equal(log.status, true);
        })
    });

  });

  describe('Board closing', () => {

    it('should allow to close board', () => {
      return Promise.resolve()
        .then(() => roles2Library.setRootUser(root, true))
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.closeBoard(boardId, {from: root}))
        .then(() => boardController.getBoardStatus(boardId))
        .then(asserts.equal(false));
    });

    it.skip('should NOT allow to close board not by root', () => {
      return Promise.resolve()
        .then(() => roles2Library.setRootUser(root, true))
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.closeBoard(boardId, {from: moderator}))
        .then(() => boardController.getBoardStatus.call(boardId))
        .then(asserts.equal(true));
    });

    it('should NOT allow to close board twice', () => {
      return Promise.resolve()
        .then(() => roles2Library.setRootUser(root, true))
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.closeBoard(boardId, {from: root}))
        .then(() => boardController.closeBoard.call(boardId, {from: root}))
        .then(assert.isFalse);
    });

    it('should emit "Boaed Closed" event', () => {
      return Promise.resolve()
        .then(() => roles2Library.setRootUser(root, true))
        .then(() => boardController.createBoard(boardName, boardDescription, boardTags, boardTagsArea, boardTagsCategory, {from: moderator}))
        .then(() => boardController.closeBoard(boardId, {from: root}))
        .then(tx => {
          assert.equal(tx.logs.length, 1);
          assert.equal(tx.logs[0].address, multiEventsHistory.address);
          assert.equal(tx.logs[0].event, 'BoardClosed');
          const log = tx.logs[0].args;
          assert.equal(log.self, boardController.address);
          assert.equal(log.boardId.toString(), '1');
          assert.equal(log.status, false);
        })
    });

  });

});
