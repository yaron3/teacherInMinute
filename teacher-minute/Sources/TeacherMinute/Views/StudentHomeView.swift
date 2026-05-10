//
//  StudentHomeView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct StudentHomeView: View {
    @State var viewModel = StudentHomeViewModel()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AppTopHeader(
                    avatarSystemImage: "person.crop.circle.fill",
                    eyebrow: "Welcome back",
                    name: viewModel.name,
                    showNotificationBadge: true
                )
                .padding(.top, 18)

                askTeacherCard
                    .padding(.top, 20)

                sectionHeader(title: "Pricing Options", actionTitle: "Compare all") {
                    // TODO
                }
                .padding(.top, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(viewModel.pricingOptions) { option in
                            PricingCard(option: option) {
                                viewModel.selectTier(option)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
                .padding(.top, 10)

                tipsCard
                    .padding(.top, 28)

                sectionHeader(title: "Recent Lessons", actionTitle: "View all") {
                    viewModel.viewAllLessons()
                }
                .padding(.top, 28)

                VStack(spacing: 12) {
                    ForEach(viewModel.recentLessons) { lesson in
                        RecentLessonRow(lesson: lesson)
                    }
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
        .task {
            await viewModel.loadProfile()
            await viewModel.loadTeachingSubjects()
        }
        .sheet(isPresented: $viewModel.showAskTeacherSheet) {
            AskTeacherSheet(viewModel: viewModel)
        }
        .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    var askTeacherCard: some View {
        Button {
            viewModel.askTeacher()
        } label: {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [Color.appPink, Color.appPurple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 116, height: 116)
                    .offset(x: 34, y: -26)

                VStack(alignment: .leading, spacing: 0) {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 58, height: 58)
                        .overlay {
                            Image(systemName: "building.columns.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                    Spacer()

                    Text("Ask a math teacher")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Connect instantly • Per-minute billing")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.top, 6)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)

                Circle()
                    .fill(.white)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.appPink)
                    }
                    .padding(.top, 36)
                    .padding(.trailing, 20)
            }
            .frame(height: 148)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.appPink.opacity(0.25), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }

    var tipsCard: some View {
        RoundedInfoCard {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(Color.yellow.opacity(0.2))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.appOrange)
                    }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Tips for faster matches")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.appPrimaryText)

                    tipLine("Upload a clear photo of your math problem")
                    tipLine("Specify the exact topic (e.g., “Derivatives”)")
                }

                Spacer()
            }
        }
    }

    func tipLine(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.appGreen)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.appSecondaryText)
        }
    }

    func sectionHeader(title: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.appPrimaryText)

            Spacer()

            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appPink)
            }
            .buttonStyle(.plain)
        }
    }
}

struct AskTeacherSheet: View {
    @Bindable var viewModel: StudentHomeViewModel
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ask a teacher")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color.appPrimaryText)
                        
                        Text("Choose the topic and describe what you need help with.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.appSecondaryText)
                            .lineSpacing(4)
                    }
                    
                    pickerSection(
                        title: "Field",
                        selection: viewModel.selectedField.isEmpty ? "Choose field" : viewModel.selectedField,
                        options: viewModel.availableFields,
                        action: viewModel.selectField
                    )
                    
                    pickerSection(
                        title: "Subfield",
                        selection: viewModel.selectedSubfield.isEmpty ? "Choose subfield" : viewModel.selectedSubfield,
                        options: viewModel.availableSubfields
                    ) { subfield in
                        viewModel.selectedSubfield = subfield
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Question")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.appPrimaryText)
                        
                        TextEditor(text: $viewModel.question)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.appPrimaryText)
                            .frame(minHeight: 120)
                            .padding(12)
                            .scrollContentBackground(.hidden)
                            .background(Color.appGrayBackground.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    
                    AuthPrimaryButton(
                        title: viewModel.isFindingTeachers ? "Finding Teachers..." : "Find Teachers",
                        systemImage: "person.2.fill",
                        isEnabled: viewModel.canFindTeachers
                    ) {
                        Task { await viewModel.findTeachers() }
                    }
                    .padding(.top, 8)
                }
                .padding(18)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Request Help")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func pickerSection(
        title: String,
        selection: String,
        options: [String],
        action: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.appPrimaryText)
            
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        action(option)
                    }
                }
            } label: {
                HStack {
                    Text(selection)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(options.isEmpty ? Color.appSecondaryText : Color.appPrimaryText)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.appSecondaryText)
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.appGrayBackground, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.025), radius: 10, x: 0, y: 5)
            }
            .disabled(options.isEmpty)
        }
    }
}

struct PricingCard: View {
    let option: PricingOption
    let action: () -> Void

    var body: some View {
        RoundedInfoCard {
            VStack(alignment: .leading, spacing: 0) {
                SmallPill(
                    title: option.name,
                    foreground: option.isHighlighted ? .white : .appPink,
                    background: option.isHighlighted ? .appPurple : .appPinkSoft
                )

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(option.price)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.appPrimaryText)

                    Text("/min")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appSecondaryText)
                }
                .padding(.top, 18)

                Text(option.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appSecondaryText)
                    .lineSpacing(4)
                    .padding(.top, 8)
                    .frame(height: 48, alignment: .top)

                Button(action: action) {
                    Text("Select Tier")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(option.isHighlighted ? .white : Color.appPrimaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(option.isHighlighted ? Color.appPurple : Color.appGrayBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
            .frame(width: 172)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(option.isHighlighted ? Color.appPurple : Color.clear, lineWidth: 2)
        }
    }
}

struct RecentLessonRow: View {
    let lesson: RecentLesson

    var body: some View {
        RoundedInfoCard {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.appPurpleSoft)
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.appPurple)
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text(lesson.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.appPrimaryText)

                    Text("\(lesson.teacher) • \(lesson.time)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.appSecondaryText)
                }

                Spacer()

                VStack(spacing: 6) {
                    SmallPill(title: "Solved", foreground: .appGreen, background: .appGreenSoft)

                    Text(lesson.duration)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.appPrimaryText)
                }
            }
        }
    }
}
#if os(iOS)
struct StudentHomeView_Previews: PreviewProvider {
  static var previews: some View {
	StudentHomeView()
  }
}
#endif
