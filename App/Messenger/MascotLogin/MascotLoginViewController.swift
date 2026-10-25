//
//  MascotLoginViewController.swift
//  Contact
//
//  Login form with a Rive mascot: its eyes follow the caret in the email field,
//  it covers its eyes while the password is being typed and peeks when the password is shown.
//  Opened from messenger Settings; submitting only drives the mascot animation.
//

import UIKit
import RiveRuntime

/// State-machine and input names inside the bundled Rive file.
struct MascotRig {
    var fileName = "login_mascot"           // login_mascot.riv in the app bundle
    var stateMachine = "Login Machine"
    /// Number 0…100 — where the mascot looks along the email field.
    var lookInput = "numLook"
    /// Boolean — paws over the eyes while the password field is focused.
    var coverEyesInput = "isChecking"
    /// Boolean — peeks through the paws while the password is visible.
    var peekInput: String? = "isPeeking"
    /// Boolean — "watching the email field" state, if the file needs one for `numLook` to take effect.
    var lookingInput: String?
    var successTrigger: String? = "trigSuccess"
    var failTrigger: String? = "trigFail"

    /// "Login screen character" from Rive Community (the file bundled as login_mascot.riv).
    /// It has no peek animation, so peeking lowers the paws instead.
    static let loginScreenCharacter = MascotRig(
        stateMachine: "State Machine 1",
        lookInput: "Look",
        coverEyesInput: "hands_up",
        peekInput: nil,
        lookingInput: "Check",
        successTrigger: "success",
        failTrigger: "fail")
}

final class MascotLoginViewController: UIViewController, UITextFieldDelegate, UIGestureRecognizerDelegate {
    private let rig: MascotRig
    private let mascot: RiveViewModel?

    let mascotView: RiveView
    let emailTextField = UITextField()
    let passwordTextField = UITextField()
    let showPasswordButton = UIButton(type: .system)
    private let signInButton = AuroraSubmitButton()
    private let header = UIView()

    init(rig: MascotRig = .loginScreenCharacter) {
        self.rig = rig
        // RiveModel(fileName:) calls fatalError (instead of throwing) when the file is missing, so check first.
        if Bundle.main.url(forResource: rig.fileName, withExtension: "riv") != nil,
           let model = try? RiveModel(fileName: rig.fileName) {
            let viewModel = RiveViewModel(model, stateMachineName: rig.stateMachine, fit: .contain)
            mascot = viewModel
            mascotView = viewModel.createRiveView()
        } else {
            mascot = nil
            mascotView = RiveView()
        }
        super.init(nibName: nil, bundle: nil)
        title = "Sign In"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureHeader()
        configureFields()
        layoutForm()
        if mascot == nil {
            showMissingFileHint()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        mascot?.play()
        signInButton.isAnimating = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        mascot?.pause()
        signInButton.isAnimating = false
    }

    // MARK: Layout

    private func configureHeader() {
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        let back = MTViews.iconButton("chevron.backward", size: 18)
        back.accessibilityLabel = "Back to Settings"
        back.accessibilityIdentifier = "contact.mascotBack"
        back.translatesAutoresizingMaskIntoConstraints = false
        back.addAction(UIAction { [weak self] _ in
            self?.view.endEditing(true)
            self?.navigationController?.popViewController(animated: true)
        }, for: .touchUpInside)
        header.addSubview(back)
        let heading = MTViews.label("Sign In", size: 17, weight: .semibold)
        heading.accessibilityTraits = .header
        heading.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(heading)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),
            back.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 4),
            back.topAnchor.constraint(equalTo: header.topAnchor),
            back.widthAnchor.constraint(equalToConstant: 44),
            back.heightAnchor.constraint(equalToConstant: 44),
            heading.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            heading.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            heading.leadingAnchor.constraint(greaterThanOrEqualTo: back.trailingAnchor, constant: 8),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -52),
        ])
    }

    private func configureFields() {
        emailTextField.placeholder = "Email"
        emailTextField.keyboardType = .emailAddress
        emailTextField.textContentType = .username
        emailTextField.autocapitalizationType = .none
        emailTextField.autocorrectionType = .no
        emailTextField.returnKeyType = .next
        emailTextField.addTarget(self, action: #selector(emailDidChange), for: .editingChanged)

        passwordTextField.placeholder = "Password"
        passwordTextField.isSecureTextEntry = true
        passwordTextField.textContentType = .password
        passwordTextField.returnKeyType = .go

        showPasswordButton.setImage(UIImage(systemName: "eye"), for: .normal)
        showPasswordButton.tintColor = .secondaryLabel
        showPasswordButton.accessibilityLabel = "Show password"
        showPasswordButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        showPasswordButton.addTarget(self, action: #selector(togglePasswordVisibility), for: .touchUpInside)
        passwordTextField.rightView = showPasswordButton
        passwordTextField.rightViewMode = .always

        for field in [emailTextField, passwordTextField] {
            field.delegate = self
            field.borderStyle = .roundedRect
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        }

        signInButton.configuration?.title = "Sign In"
        signInButton.addTarget(self, action: #selector(signIn), for: .touchUpInside)
        signInButton.accessibilityIdentifier = "mascotSubmit"
        emailTextField.accessibilityIdentifier = "mascotEmail"
        passwordTextField.accessibilityIdentifier = "mascotPassword"
    }

    private func layoutForm() {
        let stack = UIStackView(arrangedSubviews: [mascotView, emailTextField, passwordTextField, signInButton])
        stack.axis = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(24, after: mascotView)
        stack.setCustomSpacing(24, after: passwordTextField)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let guide = view.safeAreaLayoutGuide
        // The mascot gives up height first when the keyboard pushes the form up.
        let mascotHeight = mascotView.heightAnchor.constraint(equalToConstant: 280)
        mascotHeight.priority = .defaultLow
        let centered = stack.centerYAnchor.constraint(equalTo: guide.centerYAnchor)
        centered.priority = .defaultLow
        let preferredWidth = stack.widthAnchor.constraint(equalTo: guide.widthAnchor, constant: -48)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -24),
            stack.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            preferredWidth,
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
            stack.topAnchor.constraint(greaterThanOrEqualTo: header.bottomAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -16),
            centered,
            mascotHeight,
            mascotView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])

        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        dismissTap.cancelsTouchesInView = false
        dismissTap.delegate = self
        view.addGestureRecognizer(dismissTap)
    }

    private func showMissingFileHint() {
        let hint = UILabel()
        hint.text = "The character is temporarily unavailable."
        hint.font = .preferredFont(forTextStyle: .footnote)
        hint.textColor = .secondaryLabel
        hint.textAlignment = .center
        hint.numberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false
        mascotView.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: mascotView.centerXAnchor),
            hint.centerYAnchor.constraint(equalTo: mascotView.centerYAnchor),
            hint.widthAnchor.constraint(lessThanOrEqualTo: mascotView.widthAnchor),
        ])
    }

    // MARK: Mascot inputs

    /// Where the caret sits along the email field, as 0…100 for `numLook`.
    private func updateLook() {
        let textRect = emailTextField.textRect(forBounds: emailTextField.bounds)
        guard textRect.width > 0 else { return }
        let caretX: CGFloat
        if let end = emailTextField.selectedTextRange?.end {
            caretX = emailTextField.caretRect(for: end).midX
        } else {
            let font = emailTextField.font ?? .preferredFont(forTextStyle: .body)
            let width = (emailTextField.text ?? "").size(withAttributes: [.font: font]).width
            caretX = textRect.minX + width
        }
        let fraction = min(max((caretX - textRect.minX) / textRect.width, 0), 1)
        mascot?.setInput(rig.lookInput, value: Float(fraction * 100))
    }

    private func setInput(_ name: String?, _ value: Bool) {
        guard let name else { return }
        mascot?.setInput(name, value: value)
    }

    @objc private func emailDidChange() {
        updateLook()
    }

    @objc private func togglePasswordVisibility() {
        // Toggling secure entry mid-edit would wipe the text on the next keystroke; re-insert it to keep it.
        let text = passwordTextField.text ?? ""
        passwordTextField.isSecureTextEntry.toggle()
        if passwordTextField.isFirstResponder {
            passwordTextField.text = nil
            passwordTextField.insertText(text)
        }
        let visible = !passwordTextField.isSecureTextEntry
        showPasswordButton.setImage(UIImage(systemName: visible ? "eye.slash" : "eye"), for: .normal)
        showPasswordButton.accessibilityLabel = visible ? "Hide password" : "Show password"
        updatePasswordMascot(focused: passwordTextField.isFirstResponder)
    }

    /// Paws over the eyes while the password field is focused; peeks while the password is visible.
    private func updatePasswordMascot(focused: Bool) {
        let visible = !passwordTextField.isSecureTextEntry
        if let peekInput = rig.peekInput {
            setInput(rig.coverEyesInput, focused)
            setInput(peekInput, focused && visible)
        } else {
            // No peek animation in the file: lower the paws so the mascot can look.
            setInput(rig.coverEyesInput, focused && !visible)
        }
    }

    @objc private func signIn() {
        view.endEditing(true)
        let email = emailTextField.text ?? ""
        let valid = email.contains("@") && (passwordTextField.text ?? "").count >= 6
        if let trigger = valid ? rig.successTrigger : rig.failTrigger {
            mascot?.triggerInput(trigger)
        }
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    /// Taps on the fields and buttons must not dismiss the keyboard they just brought up.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UIControl)
    }

    // MARK: UITextFieldDelegate

    func textFieldDidBeginEditing(_ textField: UITextField) {
        if textField === emailTextField {
            setInput(rig.lookingInput, true)
            updateLook()
        } else if textField === passwordTextField {
            updatePasswordMascot(focused: true)
        }
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField === emailTextField {
            setInput(rig.lookingInput, false)
        } else if textField === passwordTextField {
            updatePasswordMascot(focused: false)
        }
    }

    func textFieldDidChangeSelection(_ textField: UITextField) {
        // Follow the caret when it moves without typing (tap, drag, arrow keys).
        if textField === emailTextField {
            updateLook()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === emailTextField {
            passwordTextField.becomeFirstResponder()
        } else {
            signIn()
        }
        return false
    }
}
