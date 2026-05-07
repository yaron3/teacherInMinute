//
//  TeacherIdentityVerificationView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct TeacherIdentityVerificationView: View {
    @State var viewModel = TeacherIdentityVerificationViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Step 1 of 2")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.authSecondaryText)
                    .frame(maxWidth: .infinity)

                Text("Verify Your Identity")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.authPrimaryText)
                    .padding(.top, 20)

                Text("To maintain a high-quality learning environment,\nwe need to verify your teaching credentials and\nidentity.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.authSecondaryText)
                    .lineSpacing(5)
                    .padding(.top, 8)

                verificationStatus
                    .padding(.top, 20)

                sectionTitle("Teaching Credentials")
                    .padding(.top, 22)

                Text("Upload your degree, teaching license, or relevant\ncertifications.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.authSecondaryText)
                    .lineSpacing(4)
                    .padding(.top, 8)

                UploadLargeBox(
                    title: "Tap to upload document",
                    subtitle: "PDF, JPG or PNG (Max 5MB)",
                    icon: "icloud.and.arrow.up.fill",
                    isCompleted: viewModel.hasTeachingCredentials
                ) {
                    viewModel.uploadTeachingCredentials()
                }
                .padding(.top, 12)

                sectionTitle("Government ID")
                    .padding(.top, 22)

                Text("Upload a clear photo of your passport, driver's license,\nor national ID.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.authSecondaryText)
                    .lineSpacing(4)
                    .padding(.top, 8)

                HStack(spacing: 12) {
                    IDUploadBox(
                        title: "Front Side",
                        isCompleted: viewModel.hasGovernmentIDFront
                    ) {
                        viewModel.uploadGovernmentIDFront()
                    }

                    IDUploadBox(
                        title: "Back Side",
                        isCompleted: viewModel.hasGovernmentIDBack
                    ) {
                        viewModel.uploadGovernmentIDBack()
                    }
                }
                .padding(.top, 12)

                sectionTitle("Selfie Verification")
                    .padding(.top, 22)

                Text("Take a clear selfie to match with your Government ID.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.authSecondaryText)
                    .padding(.top, 8)

                SelfieRow(isCompleted: viewModel.hasSelfie) {
                    viewModel.takeSelfie()
                }
                .padding(.top, 12)

                privacyBox
                    .padding(.top, 24)

                termsCheckbox
                    .padding(.top, 22)

                AuthPrimaryButton(
                    title: "Submit for Review",
                    systemImage: "arrow.right",
                    isEnabled: viewModel.canSubmit
                ) {
                    viewModel.submitForReview()
                }
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 18)
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
    }

    var verificationStatus: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("VERIFICATION STATUS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.authPrimaryText)

                Spacer()

                Text("Incomplete")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.authOrange)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Color.authOrange.opacity(0.12))
                    .clipShape(Capsule())
            }

            StatusRow(title: "Teaching Credentials", isDone: viewModel.hasTeachingCredentials)
            StatusRow(title: "Government ID", isDone: viewModel.hasGovernmentIDFront && viewModel.hasGovernmentIDBack)
            StatusRow(title: "Selfie Verification", isDone: viewModel.hasSelfie)
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.035), radius: 18, x: 0, y: 10)
    }

    var privacyBox: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.authPurple)

            VStack(alignment: .leading, spacing: 6) {
                Text("Your Privacy Matters")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.authPrimaryText)

                Text("Your documents are securely encrypted and\nonly used for verification purposes. They will\nnot be shared publicly on your profile.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.authSecondaryText)
                    .lineSpacing(4)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.authPurpleSoft.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    var termsCheckbox: some View {
        Button {
            viewModel.acceptedTerms.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: viewModel.acceptedTerms ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(viewModel.acceptedTerms ? Color.authPink : Color.authIcon)

                Text("I confirm that the uploaded documents are\nauthentic and belong to me. I agree to the\nVerification Terms.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.authSecondaryText)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.authPrimaryText)
    }
}

struct StatusRow: View {
    let title: String
    let isDone: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.authFieldBorder)
                .frame(width: 18, height: 18)
                .overlay {
                    Image(systemName: isDone ? "checkmark" : "circle.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(isDone ? Color.authGreen : Color.authIcon)
                }

            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color.authSecondaryText)

            Spacer()

            Circle()
                .fill(isDone ? Color.authGreen : Color.authOrange)
                .frame(width: 10, height: 10)
                .overlay {
                    if !isDone {
                        Text("!")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
        }
    }
}

struct UploadLargeBox: View {
    let title: String
    let subtitle: String
    let icon: String
    let isCompleted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Circle()
                    .fill(Color.authPinkSoft)
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: isCompleted ? "checkmark" : icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(isCompleted ? Color.authGreen : Color.authPink)
                    }

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.authPrimaryText)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.authSecondaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 116)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .foregroundStyle(Color.authFieldBorder)
            }
        }
        .buttonStyle(.plain)
    }
}

struct IDUploadBox: View {
    let title: String
    let isCompleted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Circle()
                    .fill(Color.authPurpleSoft)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: isCompleted ? "checkmark" : "person.text.rectangle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isCompleted ? Color.authGreen : Color.authPurple)
                    }

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.authPrimaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .foregroundStyle(Color.authFieldBorder)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SelfieRow: View {
    let isCompleted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.authFieldBackground)
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: isCompleted ? "checkmark" : "camera.fill")
                            .foregroundStyle(isCompleted ? Color.authGreen : Color.authPrimaryText)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Take Selfie")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.authPrimaryText)

                    Text("Ensure good lighting")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.authSecondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.authIcon)
            }
            .padding(14)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.authFieldBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}