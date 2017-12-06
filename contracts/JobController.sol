pragma solidity ^0.4.11;

import './adapters/MultiEventsHistoryAdapter.sol';
import './adapters/Roles2LibraryAndERC20LibraryAdapter.sol';
import './adapters/StorageAdapter.sol';
import './base/BitOps.sol';


contract UserLibraryInterface {
    function hasSkills(address _user, uint _area, uint _category, uint _skills) public view returns(bool);
}

contract PaymentProcessorInterface {
    function lockPayment(bytes32 _operationId, address _from, uint _value, address _contract) public returns(bool);
    function releasePayment(bytes32 _operationId, address _to, uint _value, address _change, uint _feeFromValue, uint _additionalFee, address _contract) public returns(bool);
}

contract JobController is StorageAdapter, MultiEventsHistoryAdapter, Roles2LibraryAndERC20LibraryAdapter, BitOps {
    PaymentProcessorInterface public paymentProcessor;
    UserLibraryInterface public userLibrary;

    StorageInterface.UInt jobsCount;

    StorageInterface.UIntUIntMapping jobState;
    StorageInterface.UIntAddressMapping jobClient;  // jobId => jobClient
    StorageInterface.UIntAddressMapping jobWorker;  // jobId => jobWorker
    StorageInterface.UIntBytes32Mapping jobDetailsIPFSHash;

    StorageInterface.UIntUIntMapping jobSkillsArea;  // jobId => jobSkillsArea
    StorageInterface.UIntUIntMapping jobSkillsCategory;  // jobId => jobSkillsCategory
    StorageInterface.UIntUIntMapping jobSkills;  // jobId => jobSkills

    StorageInterface.UIntUIntMapping jobStartTime;
    StorageInterface.UIntUIntMapping jobFinishTime;
    StorageInterface.UIntBoolMapping jobPaused;
    StorageInterface.UIntUIntMapping jobPausedAt;
    StorageInterface.UIntUIntMapping jobPausedFor;

    StorageInterface.UIntAddressAddressMapping jobOfferERC20Contract; // Paid with.
    StorageInterface.UIntAddressUIntMapping jobOfferRate; // Per minute.
    StorageInterface.UIntAddressUIntMapping jobOfferEstimate; // In minutes.
    StorageInterface.UIntAddressUIntMapping jobOfferOntop; // Getting to the workplace, etc.

    StorageInterface.UIntBoolMapping bindStatus;

    // At which state job has been marked as FINALIZED
    StorageInterface.UIntUIntMapping jobFinalizedAt;

    enum JobState { NOT_SET, CREATED, ACCEPTED, PENDING_START, STARTED, PENDING_FINISH, FINISHED, FINALIZED }

    event JobPosted(address indexed self, uint indexed jobId, address client, uint skillsArea, uint skillsCategory, uint skills, bytes32 detailsIPFSHash, bool bindStatus);
    event JobOfferPosted(address indexed self, uint indexed jobId, address worker, uint rate, uint estimate, uint ontop);
    event JobOfferAccepted(address indexed self, uint indexed jobId, address worker);
    event WorkStarted(address indexed self, uint indexed jobId, uint at);
    event TimeAdded(address indexed self, uint indexed jobId, uint time);  // Additional `time` in minutes
    event WorkPaused(address indexed self, uint indexed jobId, uint at);
    event WorkResumed(address indexed self, uint indexed jobId, uint at);
    event WorkFinished(address indexed self, uint indexed jobId, uint at);
    event PaymentReleased(address indexed self, uint indexed jobId);
    event JobCanceled(address indexed self, uint indexed jobId);

    modifier onlyClient(uint _jobId) {
        if (store.get(jobClient, _jobId) != msg.sender) {
            return;
        }
        _;
    }

    modifier onlyWorker(uint _jobId) {
        if (store.get(jobWorker, _jobId) != msg.sender) {
            return;
        }
        _;
    }

    modifier onlyNotClient(uint _jobId) {
        if (store.get(jobClient, _jobId) == msg.sender) {
            return;
        }
        _;
    }

    modifier onlyJobState(uint _jobId, JobState _jobState) {
        if (store.get(jobState, _jobId) != uint(_jobState)) {
            return;
        }
        _;
    }

    function JobController(Storage _store, bytes32 _crate, address _roles2Library, address _erc20Library)
        public
        StorageAdapter(_store, _crate)
        Roles2LibraryAndERC20LibraryAdapter(_roles2Library, _erc20Library)
    {
        jobsCount.init('jobsCount');

        jobState.init('jobState');
        jobClient.init('jobClient');
        jobWorker.init('jobWorker');
        jobDetailsIPFSHash.init('jobDetailsIPFSHash');

        jobSkillsArea.init('jobSkillsArea');
        jobSkillsCategory.init('jobSkillsCategory');
        jobSkills.init('jobSkills');

        jobStartTime.init('jobStartTime');
        jobFinishTime.init('jobFinishTime');
        jobPaused.init('jobPaused');
        jobPausedAt.init('jobPausedAt');
        jobPausedFor.init('jobPausedFor');

        jobOfferERC20Contract.init('jobOfferERC20Contract');
        jobOfferRate.init('jobOfferRate');
        jobOfferEstimate.init('jobOfferEstimate');
        jobOfferOntop.init('jobOfferOntop');

        jobFinalizedAt.init('jobFinalizedAt');

        bindStatus.init('bindStatus');
    }

    function setupEventsHistory(address _eventsHistory) external auth() returns(bool) {
        if (getEventsHistory() != 0x0) {
            return false;
        }
        _setEventsHistory(_eventsHistory);
        return true;
    }

    function setPaymentProcessor(PaymentProcessorInterface _paymentProcessor) external auth() returns(bool) {
        paymentProcessor = _paymentProcessor;
        return true;
    }

    function setUserLibrary(UserLibraryInterface _userLibrary) external auth() returns(bool) {
        userLibrary = _userLibrary;
        return true;
    }

    function calculateLockAmount(uint _jobId) public view returns(uint) {
        address worker = store.get(jobWorker, _jobId);
        // Lock additional working hour + 10% of resulting amount
        return (
                   (
                       store.get(jobOfferRate, _jobId, worker) * (60 + store.get(jobOfferEstimate, _jobId, worker)) +
                       store.get(jobOfferOntop, _jobId, worker)
                   ) / 10
               ) * 11;
    }

    function calculatePaycheck(uint _jobId) public view returns(uint) {
        address worker = store.get(jobWorker, _jobId);
        if (store.get(jobState, _jobId) == uint(JobState.FINISHED)) {
            // Means that participants have agreed on job completion,
            // reward should be calculated depending on worker's time spent.
            uint maxEstimatedTime = store.get(jobOfferEstimate, _jobId, worker) + 60;
            uint timeSpent = (store.get(jobFinishTime, _jobId) -
                              store.get(jobStartTime, _jobId) -
                              store.get(jobPausedFor, _jobId)) / 60;
            if (timeSpent > 60 && timeSpent <= maxEstimatedTime) {
                // Worker was doing the job for more than an hour, but less then
                // maximum estimated working time. Release money for the time
                // he has actually worked + "on top" expenses.
                return timeSpent * store.get(jobOfferRate, _jobId, worker) +
                       store.get(jobOfferOntop, _jobId, worker);

            } else if (timeSpent > maxEstimatedTime) {
                // Means worker has gone over maximum estimated time and hasnt't
                // requested more time, which is his personal responsibility, since
                // we're already giving workers additional working hour from start.
                // So we release money for maximum estimated working time + "on top".
                return maxEstimatedTime * store.get(jobOfferRate, _jobId, worker) +
                       store.get(jobOfferOntop, _jobId, worker);

            } else {
                // Worker has completed the job within just an hour, so we
                // release money for the minumum 1 working hour + "on top".
                return 60 * store.get(jobOfferRate, _jobId, worker) +
                       store.get(jobOfferOntop, _jobId, worker);
            }
        } else if (
            store.get(jobState, _jobId) == uint(JobState.STARTED) ||
            store.get(jobState, _jobId) == uint(JobState.PENDING_FINISH)
        ) {
            // Job has been canceled right after start or right before completion,
            // minimum of 1 working hour + "on top" should be released.
            return store.get(jobOfferOntop, _jobId, worker) +
                   store.get(jobOfferRate, _jobId, worker) * 60;
        } else if (
            store.get(jobState, _jobId) == uint(JobState.ACCEPTED) ||
            store.get(jobState, _jobId) == uint(JobState.PENDING_START)
        ) {
            // Job hasn't even started yet, but has been accepted,
            // release just worker "on top" expenses.
            return store.get(jobOfferOntop, _jobId, worker);
        }
    }


    function postJob(uint _area, uint _category, uint _skills, bytes32 _detailsIPFSHash)
        public
        singleOddFlag(_area)
        singleOddFlag(_category)
        hasFlags(_skills)
    returns(uint) {
        uint jobId = store.get(jobsCount) + 1;
        store.set(bindStatus, jobId, false);
        store.set(jobsCount, jobId);
        store.set(jobState, jobId, uint(JobState.CREATED));
        store.set(jobClient, jobId, msg.sender);
        store.set(jobSkillsArea, jobId, _area);
        store.set(jobSkillsCategory, jobId, _category);
        store.set(jobSkills, jobId, _skills);
        store.set(jobDetailsIPFSHash, jobId, _detailsIPFSHash);
        _emitJobPosted(jobId, msg.sender, _area, _category, _skills, _detailsIPFSHash, false);
        return jobId;
    }

    function postJobOffer(uint _jobId, address _erc20Contract, uint _rate, uint _estimate, uint _ontop)
        public
        onlyNotClient(_jobId)
        onlyJobState(_jobId, JobState.CREATED)
        onlySupportedContract(_erc20Contract)
    returns(bool) {
        if (!_validEstimate(_rate, _estimate, _ontop)) {
            return false;
        }
        if (!_hasSkillsCheck(_jobId)) {
            return false;
        }
        store.set(jobOfferERC20Contract, _jobId, msg.sender, _erc20Contract);
        store.set(jobOfferRate, _jobId, msg.sender, _rate);
        store.set(jobOfferEstimate, _jobId, msg.sender, _estimate);
        store.set(jobOfferOntop, _jobId, msg.sender, _ontop);
        _emitJobOfferPosted(_jobId, msg.sender, _rate, _estimate, _ontop);
        return true;
    }

    function _validEstimate(uint _rate, uint _estimate, uint _ontop) internal pure returns(bool) {
        if (_rate == 0 || _estimate == 0) {
            return false;
        }
        uint prev = 0;
        for (uint i = 1; i <= _estimate + 60; i++) {
            uint curr = prev + _rate;
            if (curr < prev) {
                return false;
            }
            prev = curr;
        }
        return ((prev + _ontop) / 10) * 11 > prev;
    }

    function _hasSkillsCheck (uint _jobId) internal view returns(bool) {
        return userLibrary.hasSkills(
            msg.sender,
            store.get(jobSkillsArea, _jobId),
            store.get(jobSkillsCategory, _jobId),
            store.get(jobSkills, _jobId)
        );
    }

    function acceptOffer(uint _jobId, address _worker)
        external
        onlyJobState(_jobId, JobState.CREATED)
        onlyClient(_jobId)
    returns(bool) {
        if (store.get(jobOfferRate, _jobId, _worker) == 0) {
            return false;
        }
        // Maybe incentivize by locking some money from worker?
        store.set(jobWorker, _jobId, _worker);
        if (!paymentProcessor.lockPayment(
                bytes32(_jobId),
                msg.sender,
                calculateLockAmount(_jobId),
                store.get(jobOfferERC20Contract, _jobId, _worker)
            )
        ) {
            revert();
        }
        store.set(jobState, _jobId, uint(JobState.ACCEPTED));
        _emitJobOfferAccepted(_jobId, _worker);
        return true;
    }


    function startWork(uint _jobId)
        external
        onlyJobState(_jobId, JobState.ACCEPTED)
        onlyWorker(_jobId)
    returns(bool) {
        store.set(jobState, _jobId, uint(JobState.PENDING_START));
        return true;
    }

    function confirmStartWork(uint _jobId)
        external
        onlyJobState(_jobId, JobState.PENDING_START)
        onlyClient(_jobId)
    returns(bool) {
        store.set(jobState, _jobId, uint(JobState.STARTED));
        store.set(jobStartTime, _jobId, now);
        _emitWorkStarted(_jobId, now);
        return true;
    }


    function pauseWork(uint _jobId)
        external
        onlyJobState(_jobId, JobState.STARTED)
        onlyWorker(_jobId)
    returns(bool) {
        if (store.get(jobPaused, _jobId)) {
            return false;
        }
        store.set(jobPaused, _jobId, true);
        store.set(jobPausedAt, _jobId, now);
        _emitWorkPaused(_jobId, now);
        return true;
    }

    function resumeWork(uint _jobId)
        external
        onlyJobState(_jobId, JobState.STARTED)
        onlyWorker(_jobId)
    returns(bool) {
        return _resumeWork(_jobId);
    }

    function _resumeWork(uint _jobId) internal returns(bool) {
        if (!store.get(jobPaused, _jobId)) {
            return false;
        }
        store.set(jobPausedFor, _jobId, store.get(jobPausedFor, _jobId) + (now - store.get(jobPausedAt, _jobId)));
        store.set(jobPaused, _jobId, false);
        _emitWorkResumed(_jobId, now);
        return true;
    }

    function addMoreTime(uint _jobId, uint16 _additionalTime)
        external
        onlyJobState(_jobId, JobState.STARTED)
        onlyClient(_jobId)
    returns(bool) {
        if (_additionalTime == 0) {
            return false;
        }

        if (!_setNewEstimate(_jobId, _additionalTime)) {
            revert();
        }
        _emitTimeAdded(_jobId, _additionalTime);
        return true;
    }

    function _setNewEstimate(uint _jobId, uint16 _additionalTime) internal returns(bool) {
        uint jobPaymentLocked = calculateLockAmount(_jobId);
        store.set(
            jobOfferEstimate,
            _jobId,
            store.get(jobWorker, _jobId),
            store.get(jobOfferEstimate, _jobId, store.get(jobWorker, _jobId)) + _additionalTime
        );
        return paymentProcessor.lockPayment(
            bytes32(_jobId),
            msg.sender,
            calculateLockAmount(_jobId) - jobPaymentLocked,
            store.get(jobOfferERC20Contract, _jobId, store.get(jobWorker, _jobId))
        );
    }


    function endWork(uint _jobId)
        external
        onlyJobState(_jobId, JobState.STARTED)
        onlyWorker(_jobId)
    returns(bool) {
        _resumeWork(_jobId);  // In case worker have forgotten about paused timer
        store.set(jobState, _jobId, uint(JobState.PENDING_FINISH));
        return true;
    }

    function confirmEndWork(uint _jobId)
        external
        onlyJobState(_jobId, JobState.PENDING_FINISH)
        onlyClient(_jobId)
    returns(bool) {
        store.set(jobState, _jobId, uint(JobState.FINISHED));
        store.set(jobFinishTime, _jobId, now);
        _emitWorkFinished(_jobId, now);
        return true;
    }


    function cancelJob(uint _jobId) external onlyClient(_jobId) returns(bool) {
        if (
            store.get(jobState, _jobId) != uint(JobState.ACCEPTED) &&
            store.get(jobState, _jobId) != uint(JobState.PENDING_START) &&
            store.get(jobState, _jobId) != uint(JobState.STARTED) &&
            store.get(jobState, _jobId) != uint(JobState.PENDING_FINISH)
        ) {
            return false;
        }

        uint payCheck = calculatePaycheck(_jobId);
        address worker = store.get(jobWorker, _jobId);
        if (!paymentProcessor.releasePayment(
            bytes32(_jobId),
            worker,
            payCheck,
            store.get(jobClient, _jobId),
            payCheck,
            0,
            store.get(jobOfferERC20Contract, _jobId, worker)
            )
        ) {
            return false;
        }
        store.set(jobFinalizedAt, _jobId, getJobState(_jobId));
        store.set(jobState, _jobId, uint(JobState.FINALIZED));
        _emitJobCanceled(_jobId);
        return true;
    }

    function releasePayment(uint _jobId) public onlyJobState(_jobId, JobState.FINISHED) returns(bool) {
        uint payCheck = calculatePaycheck(_jobId);
        address worker = store.get(jobWorker, _jobId);
        if (!paymentProcessor.releasePayment(
            bytes32(_jobId),
            worker,
            payCheck,
            store.get(jobClient, _jobId),
            payCheck,
            0,
            store.get(jobOfferERC20Contract, _jobId, worker)
            )
        ) {
            return false;
        }
        store.set(jobFinalizedAt, _jobId, getJobState(_jobId));
        store.set(jobState, _jobId, uint(JobState.FINALIZED));
        _emitPaymentReleased(_jobId);
        return true;
    }

    function getJobsCount() public view returns(uint) {
        return store.get(jobsCount);
    }

    function getJobClient(uint _jobId) public view returns(address) {
        return store.get(jobClient, _jobId);
    }

    function getJobWorker(uint _jobId) public view returns(address) {
        return store.get(jobWorker, _jobId);
    }

    function getJobSkillsArea(uint _jobId) public view returns(uint) {
        return store.get(jobSkillsArea, _jobId);
    }

    function getJobSkillsCategory(uint _jobId) public view returns(uint) {
        return store.get(jobSkillsCategory, _jobId);
    }

    function getJobSkills(uint _jobId) public view returns(uint) {
        return store.get(jobSkills, _jobId);
    }

    function getJobDetailsIPFSHash(uint _jobId) public view returns(bytes32) {
        return store.get(jobDetailsIPFSHash, _jobId);
    }

    function getJobState(uint _jobId) public view returns(uint) {
        return uint(store.get(jobState, _jobId));
    }

    function getFinalState(uint _jobId) public view returns(uint) {
        return store.get(jobFinalizedAt, _jobId);
    }

    function _emitJobPosted(
        uint _jobId,
        address _client,
        uint _skillsArea,
        uint _skillsCategory,
        uint _skills,
        bytes32 _detailsIPFSHash,
        bool _bindStatus
    ) internal {
        JobController(getEventsHistory()).emitJobPosted(
            _jobId,
            _client,
            _skillsArea,
            _skillsCategory,
            _skills,
            _detailsIPFSHash,
            _bindStatus
        );
    }

    function _emitJobOfferPosted(
        uint _jobId,
        address _worker,
        uint _rate,
        uint _estimate,
        uint _ontop
    ) internal {
        JobController(getEventsHistory()).emitJobOfferPosted(
            _jobId,
            _worker,
            _rate,
            _estimate,
            _ontop
        );
    }

    function _emitJobOfferAccepted(uint _jobId, address _worker) internal {
        JobController(getEventsHistory()).emitJobOfferAccepted(_jobId, _worker);
    }

    function _emitWorkStarted(uint _jobId, uint _at) internal {
        JobController(getEventsHistory()).emitWorkStarted(_jobId, _at);
    }

    function _emitWorkPaused(uint _jobId, uint _at) internal {
        JobController(getEventsHistory()).emitWorkPaused(_jobId, _at);
    }

    function _emitWorkResumed(uint _jobId, uint _at) internal {
        JobController(getEventsHistory()).emitWorkResumed(_jobId, _at);
    }

    function _emitTimeAdded(uint _jobId, uint _time) internal {
        JobController(getEventsHistory()).emitTimeAdded(_jobId, _time);
    }

    function _emitWorkFinished(uint _jobId, uint _at) internal {
        JobController(getEventsHistory()).emitWorkFinished(_jobId, _at);
    }

    function _emitPaymentReleased(uint _jobId) internal {
        JobController(getEventsHistory()).emitPaymentReleased(_jobId);
    }

    function _emitJobCanceled(uint _jobId) internal {
        JobController(getEventsHistory()).emitJobCanceled(_jobId);
    }

    function emitJobPosted(
        uint _jobId,
        address _client,
        uint _skillsArea,
        uint _skillsCategory,
        uint _skills,
        bytes32 _detailsIPFSHash,
        bool _bindStatus
    )
    public {
        JobPosted(_self(), _jobId, _client, _skillsArea, _skillsCategory, _skills, _detailsIPFSHash, _bindStatus);
    }

    function emitJobOfferPosted(uint _jobId, address _worker, uint _rate, uint _estimate, uint _ontop) public {
        JobOfferPosted(_self(), _jobId, _worker, _rate, _estimate, _ontop);
    }

    function emitJobOfferAccepted(uint _jobId, address _worker) public {
        JobOfferAccepted(_self(), _jobId, _worker);
    }

    function emitWorkStarted(uint _jobId, uint _at) public {
        WorkStarted(_self(), _jobId, _at);
    }

    function emitWorkPaused(uint _jobId, uint _at) public {
        WorkPaused(_self(), _jobId, _at);
    }

    function emitWorkResumed(uint _jobId, uint _at) public {
        WorkResumed(_self(), _jobId, _at);
    }

    function emitTimeAdded(uint _jobId, uint _time) public {
        TimeAdded(_self(), _jobId, _time);
    }

    function emitWorkFinished(uint _jobId, uint _at) public {
        WorkFinished(_self(), _jobId, _at);
    }

    function emitPaymentReleased(uint _jobId) public {
        PaymentReleased(_self(), _jobId);
    }

    function emitJobCanceled(uint _jobId) public {
        JobCanceled(_self(), _jobId);
    }
}
