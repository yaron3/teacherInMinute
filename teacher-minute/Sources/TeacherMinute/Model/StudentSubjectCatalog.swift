//
//  StudentSubjectCatalog.swift
//  teacher-minute
//
// The fixed catalog of subjects shown in the student home "Available
// Subjects" grid. Each entry's visibility is additionally gated by a Remote
// Config flag `enable_<key>` (see `StudentHomeViewModel.isSubjectEnabled`).

import Foundation

struct StudentSubjectCatalogItem: Identifiable {
  let key: String
  let title: String
  let teacherCount: Int
  let topics: String
  let systemImage: String

  var id: String { key }
}

enum StudentSubjectCatalog {
  static let items: [StudentSubjectCatalogItem] = [
    StudentSubjectCatalogItem(key: "math", title: "Math", teacherCount: 78, topics: "Algebra, trigonometry, 5 units", systemImage: "ruler.fill"),
    StudentSubjectCatalogItem(key: "physics", title: "Physics", teacherCount: 41, topics: "Mechanics, electricity, optics", systemImage: "bolt.fill"),
    StudentSubjectCatalogItem(key: "chemistry", title: "Chemistry", teacherCount: 33, topics: "Organic, physical, matriculation", systemImage: "testtube.2"),
    StudentSubjectCatalogItem(key: "statistics", title: "Statistics", teacherCount: 32, topics: "Probability, regression, SPSS", systemImage: "chart.bar.fill"),
    StudentSubjectCatalogItem(key: "computer_science", title: "Computer Science", teacherCount: 29, topics: "Python, algorithms, data structures", systemImage: "laptopcomputer"),
    StudentSubjectCatalogItem(key: "biology", title: "Biology", teacherCount: 24, topics: "Genetics, cells, molecular", systemImage: "leaf.fill"),
  ]

  static let keys: [String] = items.map(\.key)
}
