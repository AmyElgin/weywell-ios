import MapKit
import SwiftUI
import UIKit

struct ModerationView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var backend = BackendService.shared
  @State private var email = ""
  @State private var password = ""
  @State private var reports: [ModerationReport] = []
  @State private var loading = false
  @State private var workingID: UUID?
  @State private var error: String?
  @State private var rejectedReport: ModerationReport?
  @State private var recoveryMessage: String?
  @State private var sendingRecovery = false

  var body: some View {
    NavigationStack {
      ZStack {
        Color.weywellSky.ignoresSafeArea()
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text("TRUSTED COMMUNITY REVIEW").font(.caption.bold()).tracking(1.2)
                  .foregroundStyle(.secondary)
                Text("Report queue").font(.system(size: 31, weight: .black, design: .rounded))
              }
              Spacer()
              Button {
                dismiss()
              } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 42, height: 42).background(
                  .white, in: Circle())
              }.foregroundStyle(.primary)
            }
            if backend.isModeratorSignedIn {
              queueContent
            } else {
              signInContent
            }
          }.padding(20)
        }
      }
      .navigationBarHidden(true)
      .task { if backend.isModeratorSignedIn { await loadQueue() } }
      .confirmationDialog(
        "Reject this report?",
        isPresented: Binding(
          get: { rejectedReport != nil }, set: { if !$0 { rejectedReport = nil } }),
        titleVisibility: .visible
      ) {
        Button("Reject report", role: .destructive) {
          guard let report = rejectedReport else { return }
          rejectedReport = nil
          Task { await review(report, approve: false) }
        }
        Button("Cancel", role: .cancel) { rejectedReport = nil }
      } message: {
        Text("It will stay off the public map and its photo will remain private.")
      }
    }
  }

  private var signInContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("Private moderator access", systemImage: "lock.shield.fill").font(.headline)
        .foregroundStyle(Color.weywellAccent)
      Text(
        "Only accounts explicitly added to Weywell’s moderator list can view or action reports. If you’re the project owner, finish the one-time setup in MODERATION_SETUP.md first."
      )
      .font(.subheadline).foregroundStyle(.secondary)
      TextField("Moderator email", text: $email).textContentType(.username).keyboardType(
        .emailAddress
      )
      .textInputAutocapitalization(.never).autocorrectionDisabled().padding(13).background(
        Color.weywellMist, in: RoundedRectangle(cornerRadius: 12))
      SecureField("Password", text: $password).textContentType(.password).padding(13).background(
        Color.weywellMist, in: RoundedRectangle(cornerRadius: 12))
      Button {
        Task { await signIn() }
      } label: {
        HStack {
          Spacer()
          if loading {
            ProgressView().tint(.white)
          } else {
            Text("Sign in to review").fontWeight(.bold)
          }
          Spacer()
        }
        .padding(.vertical, 15).background(
          Color.weywellAccent, in: RoundedRectangle(cornerRadius: 14))
      }.foregroundStyle(.white).disabled(loading || email.isEmpty || password.isEmpty)
      Button {
        Task {
          sendingRecovery = true
          defer { sendingRecovery = false }
          do {
            try await backend.sendModeratorPasswordRecovery(email: email)
            recoveryMessage =
              "If this email belongs to a Weywell account, a reset link is on its way."
          } catch {
            recoveryMessage = "Couldn’t send a reset link. Check your connection and try again."
          }
        }
      } label: {
        HStack(spacing: 7) {
          if sendingRecovery { ProgressView() }
          Text("Forgot password?").font(.subheadline.weight(.semibold))
        }.frame(maxWidth: .infinity).padding(.vertical, 7)
      }
      .foregroundStyle(Color.weywellAccent).disabled(
        sendingRecovery || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      if let recoveryMessage { Text(recoveryMessage).font(.footnote).foregroundStyle(.secondary) }
      if let message = backend.moderatorError ?? error {
        Label(message, systemImage: "exclamationmark.triangle.fill").font(.footnote)
          .foregroundStyle(.orange)
      }
    }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 22))
  }

  private var queueContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("\(reports.count) awaiting review").font(.headline)
          Text("Approval makes an active report visible to everyone.").font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          Task { await loadQueue() }
        } label: {
          if loading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
        }.accessibilityLabel("Refresh report queue")
      }
      if let error {
        Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(
          .orange)
      }
      if reports.isEmpty && !loading {
        ContentUnavailableView(
          "Queue is clear", systemImage: "checkmark.seal",
          description: Text("New community reports will appear here for review.")
        )
        .padding(.vertical, 12).background(.white, in: RoundedRectangle(cornerRadius: 22))
      }
      ForEach(reports) { report in
        ModerationReportCard(
          report: report, isWorking: workingID == report.id,
          approve: { Task { await review(report, approve: true) } },
          reject: { rejectedReport = report })
      }
      Button("Sign out") {
        backend.moderatorSignOut()
        reports = []
        password = ""
        error = nil
      }.font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
    }.padding(18).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
  }

  private func signIn() async {
    loading = true
    error = nil
    defer { loading = false }
    if await backend.moderatorSignIn(email: email, password: password) {
      password = ""
      await loadQueue()
    }
  }

  private func loadQueue() async {
    loading = true
    error = nil
    defer { loading = false }
    do { reports = try await backend.fetchPendingReports() } catch {
      self.error = "Couldn’t load the moderation queue. Check your access and connection."
    }
  }

  private func review(_ report: ModerationReport, approve: Bool) async {
    workingID = report.id
    error = nil
    defer { workingID = nil }
    do {
      try await backend.reviewReport(report, approve: approve)
      reports.removeAll { $0.id == report.id }
    } catch {
      self.error =
        "Couldn’t update this report. It may already have been reviewed; refresh the queue."
    }
  }
}

struct PasswordResetView: View {
  @Environment(\.dismiss) private var dismiss
  let accessToken: String
  let onPasswordChanged: () -> Void
  @State private var password = ""
  @State private var confirmation = ""
  @State private var saving = false
  @State private var error: String?

  private var passwordsMatch: Bool { !password.isEmpty && password == confirmation }

  var body: some View {
    NavigationStack {
      ZStack {
        Color.weywellSky.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 16) {
          Label("SECURE YOUR ACCOUNT", systemImage: "lock.shield.fill")
            .font(.caption.bold()).tracking(1.2).foregroundStyle(Color.weywellAccent)
          Text("Set a new password")
            .font(.system(size: 31, weight: .black, design: .rounded))
          Text("Choose a password you’ll use to sign in to Weywell’s moderator tools.")
            .font(.subheadline).foregroundStyle(.secondary)
          SecureField("New password (8+ characters)", text: $password)
            .textContentType(.newPassword).textInputAutocapitalization(.never)
            .padding(14).background(Color.weywellMist, in: RoundedRectangle(cornerRadius: 13))
          SecureField("Confirm new password", text: $confirmation)
            .textContentType(.newPassword).textInputAutocapitalization(.never)
            .padding(14).background(Color.weywellMist, in: RoundedRectangle(cornerRadius: 13))
          if let error { Text(error).font(.footnote).foregroundStyle(.red) }
          Button {
            Task { await savePassword() }
          } label: {
            HStack {
              Spacer()
              if saving {
                ProgressView().tint(.white)
              } else {
                Text("Save password").fontWeight(.bold)
              }
              Spacer()
            }
            .padding(.vertical, 15).background(
              Color.weywellAccent, in: RoundedRectangle(cornerRadius: 14))
          }
          .foregroundStyle(.white)
          .disabled(saving || password.count < 8 || !passwordsMatch)
          Spacer(minLength: 0)
        }
        .padding(22).padding(.top, 24)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
        .padding(20)
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func savePassword() async {
    saving = true
    error = nil
    defer { saving = false }
    do {
      try await BackendService.shared.setRecoveredPassword(
        accessToken: accessToken, newPassword: password)
      onPasswordChanged()
      dismiss()
    } catch {
      self.error =
        "The reset link may have expired or already been used. Request a new one and try again."
    }
  }
}

private struct ModerationReportCard: View {
  let report: ModerationReport
  let isWorking: Bool
  let approve: () -> Void
  let reject: () -> Void
  @State private var photoURL: URL?

  private var categoryTitle: String {
    switch report.category {
    case "route_disruption": "Road closure / protest"
    case "unsafe_behaviour": "Unsafe behaviour"
    case "crime_reported": "Crime reported"
    case "neighbourhood": "Recent break-ins"
    default: "Community report"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(categoryTitle.uppercased()).font(.caption.bold()).tracking(0.8).foregroundStyle(
            Color.coral)
          Text(report.title).font(.headline)
        }
        Spacer()
        Text(report.reportedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
      }
      Label(report.locationText, systemImage: "mappin.and.ellipse").font(.subheadline)
      Text(report.detail).font(.subheadline).foregroundStyle(.secondary)
      if let photoURL {
        AsyncImage(url: photoURL) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          } else {
            ProgressView().frame(maxWidth: .infinity).frame(height: 180)
          }
        }.frame(maxWidth: .infinity).frame(height: 180).clipShape(
          RoundedRectangle(cornerRadius: 13))
      }
      HStack(spacing: 10) {
        Button(action: reject) {
          Label("Reject", systemImage: "xmark.circle.fill").frame(maxWidth: .infinity).padding(
            .vertical, 11
          ).background(Color.weywellMist, in: RoundedRectangle(cornerRadius: 12))
        }.foregroundStyle(.red).disabled(isWorking)
        Button(action: approve) {
          Label("Approve", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity).padding(
            .vertical, 11
          ).background(Color.weywellMint, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(
            .white)
        }.disabled(isWorking)
      }
      if isWorking { ProgressView().frame(maxWidth: .infinity) }
    }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18))
      .task(id: report.photoPath) {
        if let path = report.photoPath {
          photoURL = await BackendService.shared.moderatorPhotoURL(for: path)
        }
      }
  }
}
