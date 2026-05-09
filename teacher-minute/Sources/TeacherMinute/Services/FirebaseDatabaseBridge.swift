//
//  FirebaseDatabaseBridge.swift
//  teacher-minute
//
//  Provides Android/Kotlin implementations of the Firebase Realtime Database
//  types used by TeacherPresenceService.
//
//  Pattern follows SkipFirebaseDatabase.swift: wrap ALL code in BOTH
//  #if !SKIP_BRIDGE and #if SKIP so that:
//    • iOS SKIP_BRIDGE pass: file is empty → no bridge code generated
//    • Android SKIP transpilation: full Kotlin output
//

#if !SKIP_BRIDGE
#if SKIP

import SkipFirebaseCore
import kotlinx.coroutines.tasks.await

// MARK: - DataEventType

public enum DataEventType {
  case value
  case childAdded
  case childChanged
  case childRemoved
  case childMoved
}

// MARK: - DataSnapshot

public final class DataSnapshot {
  let snap: com.google.firebase.database.DataSnapshot
  
  init(_ snap: com.google.firebase.database.DataSnapshot) {
	self.snap = snap
  }
  
  public var key: String {
	snap.getKey() ?? ""
  }
  
  public var value: Any? {
	snap.value as Any?
  }
  
  public var children: [DataSnapshot] {
	var list: [DataSnapshot] = []
	let iter = snap.getChildren().iterator()
	while iter.hasNext() {
	  if let child = iter.next() as? com.google.firebase.database.DataSnapshot {
		list.append(DataSnapshot(child))
	  }
	}
	return list
  }
  
  public var childrenCount: Int {
	Int(snap.getChildrenCount())
  }
  
  public func childSnapshot(forPath path: String) -> DataSnapshot {
	DataSnapshot(snap.child(path))
  }
  
  public func hasChild(_ path: String) -> Bool {
	snap.hasChild(path)
  }
  
  public func exists() -> Bool {
	snap.exists()
  }
}

// MARK: - DatabaseReference

public final class DatabaseReference {
  let ref: com.google.firebase.database.DatabaseReference
  
  init(_ ref: com.google.firebase.database.DatabaseReference) {
	self.ref = ref
  }
  
  public func child(_ path: String) -> DatabaseReference {
	DatabaseReference(ref.child(path))
  }
  
  public func setValue(_ value: Any?) {
	ref.setValue(value)
	()
  }
  
  @discardableResult
  public func observe(_ eventType: DataEventType,
					  with block: @escaping (DataSnapshot) -> Void) -> UInt {
	let listener = SkipValueEventListener(block: block)
	ref.addValueEventListener(listener)
	let handle = DatabaseReference.nextHandle
	DatabaseReference.nextHandle += 1
	DatabaseReference.listenerRegistry[handle] = ListenerEntry(ref: ref, listener: listener)
	return UInt(handle)
  }
  
  public func removeObserver(withHandle handle: UInt) {
	let key = Int(handle)
	if let entry = DatabaseReference.listenerRegistry.removeValue(forKey: key) {
	  entry.ref.removeEventListener(entry.listener as com.google.firebase.database.ValueEventListener)
	}
  }
  
  private struct ListenerEntry {
	let ref: com.google.firebase.database.DatabaseReference
	let listener: SkipValueEventListener
  }
  
  private static var nextHandle: Int = 1
  private static var listenerRegistry: [Int: ListenerEntry] = [:]
}

// MARK: - SkipValueEventListener (private — not bridged to iOS)

private final class SkipValueEventListener: com.google.firebase.database.ValueEventListener {
  let block: (DataSnapshot) -> Void
  
  init(block: @escaping (DataSnapshot) -> Void) {
	self.block = block
  }
  
  override func onDataChange(_ snapshot: com.google.firebase.database.DataSnapshot) {
	block(DataSnapshot(snapshot))
	()
  }
  
  override func onCancelled(_ error: com.google.firebase.database.DatabaseError) {
	// TODO: surface the error through an error callback if needed.
  }
}

// MARK: - Database

public final class Database {
  let db: com.google.firebase.database.FirebaseDatabase
  
  init(_ db: com.google.firebase.database.FirebaseDatabase) {
	self.db = db
  }
  
  public static func database() -> Database {
	Database(com.google.firebase.database.FirebaseDatabase.getInstance())
  }
  
  public func reference(withPath path: String) -> DatabaseReference {
	DatabaseReference(db.getReference(path))
  }
  
  public func reference() -> DatabaseReference {
	DatabaseReference(db.getReference())
  }
}

#endif // SKIP
#endif // !SKIP_BRIDGE
