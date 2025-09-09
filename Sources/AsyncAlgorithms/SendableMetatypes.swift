#if compiler(>=6.2)
public typealias _AsyncSequenceSendableMetatype = SendableMetatype
public typealias _AsyncIteratorSendableMetatype = SendableMetatype
#else
public typealias _AsyncSequenceSendableMetatype = Any
public typealias _AsyncIteratorSendableMetatype = Any
#endif