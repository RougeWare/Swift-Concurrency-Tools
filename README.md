# ConcurrencyTools

Makes Swift concurrency easier



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
