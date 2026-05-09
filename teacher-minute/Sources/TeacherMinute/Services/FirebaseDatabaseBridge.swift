//
//  FirebaseDatabaseBridge.swift
//  teacher-minute
//
//  Provides Android/Kotlin implementations of the Firebase Realtime Database
//  types used by TeacherPresenceService.
//

#if SKIP

import SkipFirebaseCore

private func dbLog(_ msg: String) {
  print(msg)
}
private func dbErr(_ msg: String) {
  print(msg)
}

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
	dbLog("[Bridge] child('\(path)') on \(ref.toString())")
	return DatabaseReference(ref.child(path))
  }
  
  public func setValue(_ value: Any?) {
	dbLog("[Bridge] setValue(\(String(describing: value))) on \(ref.toString())")
	ref.setValue(value)
	  .addOnSuccessListener { _ in
		dbLog("[Bridge] setValue succeeded on \(ref.toString())")
	  }
	  .addOnFailureListener { error in
		dbErr("[Bridge] setValue failed on \(ref.toString()): \(error.message ?? String(describing: error))")
	  }
  }
  
  @discardableResult
  public func observe(_ eventType: DataEventType,
					  with block: @escaping (DataSnapshot) -> Void) -> UInt {
	let path = ref.toString()
	dbLog("[Bridge] observe(.value) attaching ValueEventListener on \(path)")
	let listener = SkipValueEventListener(block: block, path: path)
	ref.addValueEventListener(listener)
	let handle = DatabaseReference.nextHandle
	DatabaseReference.nextHandle += 1
	DatabaseReference.listenerRegistry[handle] = ListenerEntry(ref: ref, listener: listener)
	dbLog("[Bridge] observer attached handle=\(handle) path=\(path)")
	return UInt(handle)
  }
  
  public func removeObserver(withHandle handle: UInt) {
	let key = Int(handle)
	dbLog("[Bridge] removeObserver handle=\(key)")
	if let entry = DatabaseReference.listenerRegistry.removeValue(forKey: key) {
	  entry.ref.removeEventListener(entry.listener as com.google.firebase.database.ValueEventListener)
	  dbLog("[Bridge] observer removed handle=\(key)")
	} else {
	  dbErr("[Bridge] removeObserver no entry found for handle=\(key)")
	}
  }
  
  private struct ListenerEntry {
	let ref: com.google.firebase.database.DatabaseReference
	let listener: SkipValueEventListener
  }
  
  private static var nextHandle: Int = 1
  private static var listenerRegistry: [Int: ListenerEntry] = [:]
}

// MARK: - SkipValueEventListener

private final class SkipValueEventListener: com.google.firebase.database.ValueEventListener {
  let block: (DataSnapshot) -> Void
  let path: String
  
  init(block: @escaping (DataSnapshot) -> Void, path: String) {
	self.block = block
	self.path = path
  }
  
  override func onDataChange(_ snapshot: com.google.firebase.database.DataSnapshot) {
	let count = snapshot.getChildrenCount()
	dbLog("[Bridge] onDataChange path=\(path) childrenCount=\(count) exists=\(snapshot.exists())")
	let rawValue = snapshot.value
	dbLog("[Bridge] onDataChange rawValue type=\(rawValue != nil ? String(describing: type(of: rawValue!)) : "nil") value=\(String(describing: rawValue))")
	block(DataSnapshot(snapshot))
	dbLog("[Bridge] onDataChange block returned")
  }
  
  override func onCancelled(_ error: com.google.firebase.database.DatabaseError) {
	dbErr("[Bridge] onCancelled code=\(error.code) message=\(error.message) path=\(path)")
  }
}

// MARK: - Database

public final class Database {
  let db: com.google.firebase.database.FirebaseDatabase
  
  init(_ db: com.google.firebase.database.FirebaseDatabase) {
	self.db = db
  }
  
  public static func database() -> Database {
	let url = "https://teacher-in-a-moment-default-rtdb.firebaseio.com"
	dbLog("[Bridge] Database.database() getting instance for url=\(url)")
	let instance = com.google.firebase.database.FirebaseDatabase.getInstance(url)
	dbLog("[Bridge] FirebaseDatabase instance obtained: \(instance.toString())")
	return Database(instance)
  }
  
  public func reference(withPath path: String) -> DatabaseReference {
	dbLog("[Bridge] reference(withPath: '\(path)')")
	return DatabaseReference(db.getReference(path))
  }
  
  public func reference() -> DatabaseReference {
	dbLog("[Bridge] reference() root ref")
	return DatabaseReference(db.getReference())
  }
}

#endif
