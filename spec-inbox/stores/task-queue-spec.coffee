Actions = require '../../src/flux/actions'
TaskQueue = require '../../src/flux/stores/task-queue'
Task = require '../../src/flux/tasks/task'

{isTempId} = require '../../src/flux/models/utils'

{APIError,
 OfflineError,
 TimeoutError} = require '../../src/flux/errors'

class TaskSubclassA extends Task
  constructor: (val) -> @aProp = val # forgot to call super

class TaskSubclassB extends Task
  constructor: (val) -> @bProp = val; super

describe "TaskQueue", ->
  makeUnstartedTask = (task) ->
    TaskQueue._initializeTask(task)
    return task

  makeLocalStarted = (task) ->
    TaskQueue._initializeTask(task)
    task.queueState.isProcessing = true
    return task

  makeLocalFailed = (task) ->
    TaskQueue._initializeTask(task)
    task.queueState.performedLocal = Date.now()
    return task

  makeRemoteStarted = (task) ->
    TaskQueue._initializeTask(task)
    task.queueState.isProcessing = true
    task.queueState.remoteAttempts = 1
    task.queueState.performedLocal = Date.now()
    return task

  makeRemoteSuccess = (task) ->
    TaskQueue._initializeTask(task)
    task.queueState.remoteAttempts = 1
    task.queueState.performedLocal = Date.now()
    task.queueState.performedRemote = Date.now()
    return task

  makeRemoteFailed = (task) ->
    TaskQueue._initializeTask(task)
    task.queueState.remoteAttempts = 1
    task.queueState.performedLocal = Date.now()
    return task

  beforeEach ->
    TaskQueue._onlineStatus = true
    @task              = new Task()
    @unstartedTask     = makeUnstartedTask(new Task())
    @localStarted      = makeLocalStarted(new Task())
    @localFailed       = makeLocalFailed(new Task())
    @remoteStarted     = makeRemoteStarted(new Task())
    @remoteSuccess     = makeRemoteSuccess(new Task())
    @remoteFailed      = makeRemoteFailed(new Task())

  unstartedTask = (task) ->
    taks.queueState.shouldRetry = false
    taks.queueState.isProcessing = false
    taks.queueState.remoteAttempts = 0
    taks.queueState.perfomredLocal = false
    taks.queueState.performedRemote = false
    taks.queueState.notifiedOffline = false

  startedTask = (task) ->
    taks.queueState.shouldRetry = false
    taks.queueState.isProcessing = true
    taks.queueState.remoteAttempts = 0
    taks.queueState.perfomredLocal = false
    taks.queueState.performedRemote = false
    taks.queueState.notifiedOffline = false

  localTask = (task) ->
    taks.queueState.shouldRetry = false
    taks.queueState.isProcessing = true
    taks.queueState.remoteAttempts = 0
    taks.queueState.perfomredLocal = false
    taks.queueState.performedRemote = false
    taks.queueState.notifiedOffline = false

  afterEach ->
    TaskQueue._queue = []
    TaskQueue._completed = []

  describe "enqueue", ->
    it "makes sure you've queued a real task", ->
      expect( -> TaskQueue.enqueue("asamw")).toThrow()

    it "adds it to the queue", ->
      TaskQueue.enqueue(@task)
      expect(TaskQueue._queue.length).toBe 1

    it "notifies the queue should be processed", ->
      spyOn(TaskQueue, "_processTask")
      spyOn(TaskQueue, "_processQueue").andCallThrough()

      TaskQueue.enqueue(@task)

      expect(TaskQueue._processQueue).toHaveBeenCalled()
      expect(TaskQueue._processTask).toHaveBeenCalledWith(@task)
      expect(TaskQueue._processTask.calls.length).toBe 1

    it "ensures all tasks have an id", ->
      TaskQueue.enqueue(new TaskSubclassA())
      TaskQueue.enqueue(new TaskSubclassB())
      expect(isTempId(TaskQueue._queue[0].id)).toBe true
      expect(isTempId(TaskQueue._queue[1].id)).toBe true

    it "dequeues Obsolete tasks", ->
      class KillsTaskA extends Task
        constructor: ->
        shouldDequeueOtherTask: (other) -> other instanceof TaskSubclassA

      taskToDie = makeRemoteFailed(new TaskSubclassA())

      spyOn(TaskQueue, "dequeue").andCallThrough()
      spyOn(taskToDie, "abort")

      TaskQueue._queue = [taskToDie, @remoteFailed]
      TaskQueue.enqueue(new KillsTaskA())

      expect(TaskQueue._queue.length).toBe 2
      expect(TaskQueue.dequeue).toHaveBeenCalledWith(taskToDie, silent: true)
      expect(TaskQueue.dequeue.calls.length).toBe 1
      expect(taskToDie.abort).toHaveBeenCalled()

  describe "dequeue", ->
    beforeEach ->
      TaskQueue._queue = [@unstartedTask,
                          @localStarted,
                          @remoteStarted,
                          @remoteFailed]

    it "grabs the task by object", ->
      found = TaskQueue._parseArgs(@remoteStarted)
      expect(found).toBe @remoteStarted

    it "grabs the task by id", ->
      found = TaskQueue._parseArgs(@remoteStarted.id)
      expect(found).toBe @remoteStarted

    it "throws an error if the task isn't found", ->
      expect( -> TaskQueue.dequeue("bad")).toThrow()

    it "doesn't abort unstarted tasks", ->
      spyOn(@unstartedTask, "abort")
      TaskQueue.dequeue(@unstartedTask, silent: true)
      expect(@unstartedTask.abort).not.toHaveBeenCalled()

    it "aborts local tasks in progress", ->
      spyOn(@localStarted, "abort")
      TaskQueue.dequeue(@localStarted, silent: true)
      expect(@localStarted.abort).toHaveBeenCalled()

    it "aborts remote tasks in progress", ->
      spyOn(@remoteStarted, "abort")
      TaskQueue.dequeue(@remoteStarted, silent: true)
      expect(@remoteStarted.abort).toHaveBeenCalled()

    it "calls cleanup on aborted tasks", ->
      spyOn(@remoteStarted, "cleanup")
      TaskQueue.dequeue(@remoteStarted, silent: true)
      expect(@remoteStarted.cleanup).toHaveBeenCalled()

    it "aborts stalled remote tasks", ->
      spyOn(@remoteFailed, "abort")
      TaskQueue.dequeue(@remoteFailed, silent: true)
      expect(@remoteFailed.abort).toHaveBeenCalled()

    it "doesn't abort if it's fully done", ->
      TaskQueue._queue.push @remoteSuccess
      spyOn(@remoteSuccess, "abort")
      TaskQueue.dequeue(@remoteSuccess, silent: true)
      expect(@remoteSuccess.abort).not.toHaveBeenCalled()

    it "moves it from the queue", ->
      TaskQueue.dequeue(@remoteStarted, silent: true)
      expect(TaskQueue._queue.length).toBe 3
      expect(TaskQueue._completed.length).toBe 1

    it "marks it as no longer processing", ->
      TaskQueue.dequeue(@remoteStarted, silent: true)
      expect(@remoteStarted.queueState.isProcessing).toBe false

    it "notifies the queue has been updated", ->
      spyOn(TaskQueue, "_processQueue")

      TaskQueue.dequeue(@remoteStarted)

      expect(TaskQueue._processQueue).toHaveBeenCalled()
      expect(TaskQueue._processQueue.calls.length).toBe 1

  describe "process Task", ->
    it "doesn't process processing tasks", ->
      spyOn(@remoteStarted, "performLocal")
      spyOn(@remoteStarted, "performRemote")
      TaskQueue._processTask(@remoteStarted)
      expect(@remoteStarted.performLocal).not.toHaveBeenCalled()
      expect(@remoteStarted.performRemote).not.toHaveBeenCalled()

    it "doesn't process blocked tasks", ->
      class BlockedByTaskA extends Task
        constructor: ->
        shouldWaitForTask: (other) -> other instanceof TaskSubclassA

      blockedByTask = new BlockedByTaskA()
      spyOn(blockedByTask, "performLocal")
      spyOn(blockedByTask, "performRemote")

      blockingTask = makeRemoteFailed(new TaskSubclassA())

      TaskQueue._queue = [blockingTask, @remoteFailed]
      TaskQueue.enqueue(blockedByTask)

      expect(TaskQueue._queue.length).toBe 3
      expect(blockedByTask.performLocal).not.toHaveBeenCalled()
      expect(blockedByTask.performRemote).not.toHaveBeenCalled()

    it "doesn't block itself", ->
      class BlockingTask extends Task
        constructor: ->
        shouldWaitForTask: (other) -> other instanceof BlockingTask

      blockedByTask = new BlockingTask()
      spyOn(blockedByTask, "performLocal")
      spyOn(blockedByTask, "performRemote")

      blockingTask = makeRemoteFailed(new BlockingTask())

      TaskQueue._queue = [blockingTask, @remoteFailed]
      TaskQueue.enqueue(blockedByTask)

      expect(TaskQueue._queue.length).toBe 3
      expect(blockedByTask.performLocal).not.toHaveBeenCalled()
      expect(blockedByTask.performRemote).not.toHaveBeenCalled()

    it "sets the processing bit", ->
      spyOn(@unstartedTask, "performLocal").andCallFake -> Promise.resolve()
      TaskQueue._processTask(@unstartedTask)
      expect(@unstartedTask.queueState.isProcessing).toBe true

    it "performs local if it's a fresh task", ->
      spyOn(@unstartedTask, "performLocal").andCallFake -> Promise.resolve()
      TaskQueue._processTask(@unstartedTask)
      expect(@unstartedTask.performLocal).toHaveBeenCalled()

  describe "performLocal", ->
    it "on success it marks it as complete with the timestamp", ->
      spyOn(@unstartedTask, "performLocal").andCallFake -> Promise.resolve()
      spyOn(@unstartedTask, "performRemote").andCallFake -> Promise.resolve()
      runs ->
        TaskQueue.enqueue(@unstartedTask)
      waitsFor =>
        @unstartedTask.queueState.performedLocal isnt false
      runs ->
        expect(@unstartedTask.queueState.performedLocal).toBeGreaterThan 0

    it "throws an error if it fails", ->
      spyOn(@unstartedTask, "performLocal").andCallFake -> Promise.reject("boo")
      spyOn(@unstartedTask, "performRemote").andCallFake -> Promise.resolve()
      runs ->
        TaskQueue.enqueue(@unstartedTask)
      waitsFor =>
        @unstartedTask.queueState.isProcessing == false
      runs ->
        expect(@unstartedTask.queueState.localError).toBe "boo"
        expect(@unstartedTask.performLocal).toHaveBeenCalled()
        expect(@unstartedTask.performRemote).not.toHaveBeenCalled()

    it "dequeues the task if it fails locally", ->
      spyOn(@unstartedTask, "performLocal").andCallFake -> Promise.reject("boo")
      spyOn(@unstartedTask, "performRemote").andCallFake -> Promise.resolve()
      runs ->
        TaskQueue.enqueue(@unstartedTask)
      waitsFor =>
        @unstartedTask.queueState.isProcessing == false
      runs ->
        expect(TaskQueue._queue.length).toBe 0
        expect(TaskQueue._completed.length).toBe 1

  describe "performRemote", ->
    beforeEach ->
      spyOn(@unstartedTask, "performLocal").andCallFake -> Promise.resolve()

    it "performs remote properly", ->
      spyOn(@unstartedTask, "performRemote").andCallFake -> Promise.resolve()
      runs ->
        TaskQueue.enqueue(@unstartedTask)
      waitsFor =>
        @unstartedTask.queueState.performedRemote isnt false
      runs ->
        expect(@unstartedTask.performLocal).toHaveBeenCalled()
        expect(@unstartedTask.performRemote).toHaveBeenCalled()

    it "dequeues on success", ->
      spyOn(@unstartedTask, "performRemote").andCallFake -> Promise.resolve()
      runs ->
        TaskQueue.enqueue(@unstartedTask)
      waitsFor =>
        @unstartedTask.queueState.isProcessing is false and
        @unstartedTask.queueState.performedRemote > 0
      runs ->
        expect(TaskQueue._queue.length).toBe 0
        expect(TaskQueue._completed.length).toBe 1

    it "notifies we're offline the first time", ->
      spyOn(TaskQueue, "_isOnline").andReturn false
      spyOn(@unstartedTask, "performRemote").andCallFake -> Promise.resolve()
      spyOn(@unstartedTask, "onError")
      runs ->
        TaskQueue.enqueue(@unstartedTask)
      waitsFor =>
        @unstartedTask.queueState.notifiedOffline == true
      runs ->
        expect(@unstartedTask.performLocal).toHaveBeenCalled()
        expect(@unstartedTask.performRemote).not.toHaveBeenCalled()
        expect(@unstartedTask.onError).toHaveBeenCalled()
        expect(@unstartedTask.queueState.isProcessing).toBe false
        expect(@unstartedTask.onError.calls[0].args[0] instanceof OfflineError).toBe true

    it "doesn't notify we're offline the second+ time", ->
      spyOn(TaskQueue, "_isOnline").andReturn false
      spyOn(@remoteFailed, "performLocal").andCallFake -> Promise.resolve()
      spyOn(@remoteFailed, "performRemote").andCallFake -> Promise.resolve()
      spyOn(@remoteFailed, "onError")
      @remoteFailed.queueState.notifiedOffline = true
      TaskQueue._queue = [@remoteFailed]
      runs ->
        TaskQueue._processQueue()
      waitsFor =>
        @remoteFailed.queueState.isProcessing is false
      runs ->
        expect(@remoteFailed.performLocal).not.toHaveBeenCalled()
        expect(@remoteFailed.performRemote).not.toHaveBeenCalled()
        expect(@remoteFailed.onError).not.toHaveBeenCalled()

    it "marks performedRemote on success", ->
      spyOn(@unstartedTask, "performRemote").andCallFake -> Promise.resolve()
      runs ->
        TaskQueue.enqueue(@unstartedTask)
      waitsFor =>
        @unstartedTask.queueState.performedRemote isnt false
      runs ->
        expect(@unstartedTask.queueState.performedRemote).toBeGreaterThan 0

    it "on failure it notifies of the error", ->
      err = new APIError
      spyOn(@unstartedTask, "performRemote").andCallFake -> Promise.reject(err)
      spyOn(@unstartedTask, "onError")
      runs ->
        TaskQueue.enqueue(@unstartedTask)
      waitsFor =>
        @unstartedTask.queueState.isProcessing is false
      runs ->
        expect(@unstartedTask.performLocal).toHaveBeenCalled()
        expect(@unstartedTask.performRemote).toHaveBeenCalled()
        expect(@unstartedTask.onError).toHaveBeenCalledWith(err)

    it "dequeues on failure", ->
      err = new APIError
      spyOn(@unstartedTask, "performRemote").andCallFake -> Promise.reject(err)
      runs ->
        TaskQueue.enqueue(@unstartedTask)
      waitsFor =>
        @unstartedTask.queueState.isProcessing is false
      runs ->
        expect(TaskQueue._queue.length).toBe 0
        expect(TaskQueue._completed.length).toBe 1

    it "on failure it sets the appropriate bits", ->
      err = new APIError
      spyOn(@unstartedTask, "performRemote").andCallFake -> Promise.reject(err)
      spyOn(@unstartedTask, "onError")
      runs ->
        TaskQueue.enqueue(@unstartedTask)
      waitsFor =>
        @unstartedTask.queueState.isProcessing is false
      runs ->
        expect(@unstartedTask.queueState.notifiedOffline).toBe false
        expect(@unstartedTask.queueState.remoteError).toBe err

  describe "under stress", ->
    beforeEach ->
      TaskQueue._queue = [@unstartedTask,
                          @remoteFailed]
    it "when all tasks pass it processes all items", ->
      for task in TaskQueue._queue
        spyOn(task, "performLocal").andCallFake -> Promise.resolve()
        spyOn(task, "performRemote").andCallFake -> Promise.resolve()
      runs ->
        TaskQueue.enqueue(new Task)
      waitsFor ->
        TaskQueue._queue.length is 0
      runs ->
        expect(TaskQueue._completed.length).toBe 3