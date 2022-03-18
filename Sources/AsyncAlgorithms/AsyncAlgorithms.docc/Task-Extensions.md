# Task Extensions

The AsyncAlgorithms package provides a number of extensions to `Task`.

## Topics

### Select

Selecting the first task to complete from a list of active tasks is a similar algorithm to `select(2)`. This has similar behavior to `TaskGroup` except that instead of child tasks this function transacts upon already running tasks and does not cancel them upon completion of the selection and does not need to await for the completion of all of the tasks in the list to select. 

- ``_Concurrency/Task/select(_:)-10kz8``
- ``_Concurrency/Task/select(_:)-6z7kp``
