//
//  Question.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 16/05/2026.
//


struct Message: Codable {
  let id: String
  let text: String
  let senderUid: String
  let senderRole: String
  let createdAt: Double
}

struct Question: Codable {
  let acceptedAt: Double
  let agoraChannel: String
  let alreadyInvited: [String]
  let createdAt: Double
  let dispatchWave: Int
  let endedAt: Double
  let endedBy: String
  let messages: [Message]
  let participants: [String]
  let photoUrls: [String]
  let state: String
  let status: String
  let studentUid: String
  let teacherId: String
  let text: String
  let topic: String
  let updatedAt: Double
}
