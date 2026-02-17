# ConcurrencyTools

Makes Swift concurrency easier



## `Semaphore`

A moderrn semaphore for a modern era.

This brings the counting semaphore into the '20s with proper concurrency semantics and a clean API.

Among other things, this allows you to pause one context to wait until another context says it's ready.

When you call `wait()` more than once before calling `signal()`, all those `wait()` callsites are paused at the same time. When you call `signal()`, it only resumes the most-recent `wait()` which hasn't yet been `signal()`ed.


```swift
let semaphore = Semaphore()

taskGroup.addTask {
    preAllocateResources()
    await semaphore.wait()
    start()
}

onUserDidRequestStart {
    semaphore.signal()
}
```


```swift
let semaphore = Semaphore()

Task {
    try await semaphore.wait(timeout: .seconds(30))
    handleSuccess()
}

self.downloadResult = await download()
semaphore.signal()
```


### Learn about semaphores

To learn more about how semaphores work, see:
https://en.wikipedia.org/wiki/Semaphore_(programming)


### Technical details
A semaphore can control access to a resource across multiple concurrency contexts through use of a traditional counting semaphore and structured concurrency.

This is an efficient implementation of a traditional counting semaphore. It will only call down to the kernel when the calling context needs to be blocked. If it does not need to block, no kernel call is made.



## `desync`

This converts an `async` function into a function with a callback. The code still runs asynchronously without blocking, but returns its result via a callback:

```swift
Task.desync {
    try await fetchAllUserData()
} callback: { [weak self] result in
    switch result in {
    case .success(let userData):
        self?.userData = userData
        
    case .failure(let error):
        log(error: error)
    }
}
```



## `onMainActor`

Simple sugar to run some sendable block on the main actor, without needing to `await` it:

```swift
Button("Download") {
    someOldApiWithBackgroundThreadCallback { data in
        onMainActor {
            self.oldApiData = data
        }
    }
}
```



## `resync`

Converts any `async` function back into a synchronous one:

```swift
let userData = try resync { try urlSession.data(from: .AppApi.userData) }
let message = try resync(urlSessionWebSocketTask.receive)
```



## Syntactic sugar

### `DispatchSemaphore.default`

You ever like... want to use a semaphore, but forget what the starting value is? Or don't care? Same here. So I made this mindless option in case you just want to make a locking semaphore.

```swift
let semaphore = DispatchSemaphore.default

someBackgroundCall {
    doSomething()
    semaphore.signal()
}

semaphore.wait()
```



### `Task.sleep(seconds:)`

Why the h*ck did Apple create an API in the year of our Lord 2021 which takes an integer number of nanoseconds, but not one that takes a `TimeInterval`??

Well, until Apple makes one, I can do that for them:

```swift
Task {
    testCondition()
    Task.sleep(seconds: 5)
    testCondition()
}
```
