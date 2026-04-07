# ConcurrencyTools

Makes Swift concurrency easier



## `AsyncBinding` & friends

For when you want the features of a binding, but need the setter/getter of that binding to be `async`.

```swift
struct App: SwiftUI.App {
    var someActor = MyActor()
    
    
    var body: some Scene {
        WindowGroup {
            ContentView(asyncResource: AsyncBinding {
                await someActor.loadResource()
            } set: {
                await someActor.setResource($0)
            })
        }
    }
}



struct ContentView: View {

    let asyncResource: AsyncBinding<AsyncResource>
    
    @State
    var lazyLoadedResource: AsyncResource? // `Optional` for this example, but `LoadingState` would be much better
    
    
    var body: some View {
        if let lazyLoadedResource {
            TextField(Binding { // TextField needs a traditional binding, and that's just fine here
                lazyLoadedResource.name
            } set: {
                Task {
                    await asyncResource.setWrappedValue($0)
                }
            })
        }
        else {
            Button("Click to load") {
                Task {
                    self.lazyLoadedResource = await asyncResource.wrappedValue
                }
            }
        }
    }
}
```

This also lets you peek at the current loading state and subscribe to changes as a Combine publisher.

**And friends!** This concept is broken into 4 types:
- `AsyncBinding`: Like a `Binding`, but async
- `ThrowingAsyncBinding`: A version of `AsyncBinding` where the setter/getter might throw an error
- `AsyncLazy`: A version of `AsyncBinding` without a setter
- `ThrowingAsyncLazy` A version of `AsyncLazy` where the initial value generator might throw an error 


Of course, the thowing variants need some extra considerations for their extra states. For example, when responding to a value changing in a `Binding` or `AsyncBinding`, you just pass a `set` function to the initializer which takes the new value. However, when the value in a `ThrowingAsyncBinding` changes, that same `set` function needs to accept a `Result` which could either be the value or the failure, and calling `.wrappedValue` might result in the error being thrown. For example:

```swift
struct App: SwiftUI.App {
    var someActor = MyDangerousActor()
    
    
    var body: some Scene {
        WindowGroup {
            ContentView(asyncResource: ThrowingAsyncBinding {
                try await someActor.loadResource()
            } set: {
                switch $0 {
                case .success(let newValue):
                    await someActor.setResource(newValue)
                    
                case .failure(let error):
                    log(error: error)
                }
            })
        }
    }
}



struct ContentView: View {

    let asyncResource: ThrowingAsyncBinding<AsyncResource>
    
    @State
    var lazyLoadedResource: AsyncResource? // `Optional` for this example, but `LoadingState` would be much better
    
    @State
    var latestError: LocalizedError?
    
    
    var body: some View {
        if let latestError {
            VStack(alignment: .leading) {
                Text("Failed to load!")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                
                Text(latestError.errorDescription ?? latestError.localizedDescription)
                if let recoverySuggestion = latestError.recoverySuggestion {
                    Text(recoverySuggestion)
                }
            }
        }
        else if let lazyLoadedResource {
            Text(lazyLoadedResource.name)
        }
        else {
            Button("Click to load") {
                Task {
                    do {
                        self.lazyLoadedResource = try await asyncResource.wrappedValue
                    }
                    catch {
                        self.lazyLoadedResource = nil
                        self.latestError = error
                    }
                }
            }
        }
    }
}
```

There's a few other ways to mutate the value inside an async binding and listen to its changes. Check out the code!



## `Mutex`

The standard concept of a [mutex](https://en.wikipedia.org/wiki/mutex), but made entirely of Swift-native structured concurrency constructs.

```swift
let counter = Mutex(0)

await withTaskGroup(of: Void.self) { group in
    for resource in resources {
        group.addTask {
            await counter.run { $0 += try resource.count }
        }
    }
}

print("Grand total resource count: \(await counter.run { $0 })")
```



## `Gate`

You can think of this as a limited version of a semaphore, built entirely on structured concurrency concepts

```swift
let gate = Gate()

Task {
    await doLotsOfWork()
    gate.resume()
}

await gate.suspend()
```



## `LoadingState` & `FailableLoadingState`

These allow you to model the current state of loading something which might fail to load.

You might think of these similarly to `Result`, but with additional cases describing the current loading state if it's not yet resolved.

```swift
switch bigResource.peekLoadingState {
    case .notStarted:
        Button("Start loading") {
            Task { _ = await asyncBinding.wrappedValue }
        }
        
    case .loading:
        ProgressView()
        
    case .success(let bigResource):
        BigResourceView(bigResource)
        
    case .failure(let failure):
        ErrorView(failue)
}
```



## Async features for `Result`

Simply adds missing `async` features to Swift's builtin `Result` type.

```swift
return await Result {
    try await loadValue()
}
```



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
let userData = try resync { try await urlSession.data(from: .AppApi.userData) }
let message = try resync(urlSessionWebSocketTask.receive)
```



## Syntactic sugar

### `DispatchSemaphore.default`

You ever like... want to use a semaphore, but forget what the starting value should be? Or don't care? Same here. So I made this mindless option in case you just want to make a locking semaphore.

```swift
let semaphore = DispatchSemaphore.default

someBackgroundCall {
    doSomething()
    semaphore.signal()
}

semaphore.wait()
```



## On the use of LLMs

The following LLMs were directed to assist with some parts of this package:
- Claude 4.5 Sonnet
- Claude 4.6 Sonnet
- GPT-OSS

These LLMs were never given direct access to the files in this package. They were directed by providing contexts and goals in web chats, and their responses were used to inform how this package was written. All code was critically inspected & reviewed by the package maintainers, regardless of how that code was written.
