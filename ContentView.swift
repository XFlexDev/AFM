import SwiftUI
import FoundationModels

struct Message: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isUser: Bool
}

struct ContentView: View {
    @State private var messages: [Message] = []
    @State private var inputText: String = ""
    @State private var chatSession = LanguageModelSession()
    @State private var contextSession = LanguageModelSession()
    @State private var contextMemory: String = ""
    @State private var isResponding = false
    @State private var isCreatingContext = false
    @State private var streamingResponse: String = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showContextSheet = false
    
    private var isModelAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available: return true
        default: return false
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Text("AFM")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                    
                    Spacer()
                    
                    if !contextMemory.isEmpty {
                        Button {
                            showContextSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "brain.head.profile")
                                Text("Konteksti")
                                    .font(.caption)
                            }
                            .foregroundStyle(.cyan)
                        }
                    }
                    
                    if !messages.isEmpty {
                        Button("Luo konteksti & uusi") {
                            createContextAndReset()
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .disabled(isCreatingContext || isResponding)
                    }
                    
                    if !isModelAvailable {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                Spacer()
                
                // Main area
                if messages.isEmpty && streamingResponse.isEmpty {
                    // Initial Gemini-style screen
                    VStack(spacing: 28) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue, .cyan, .mint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .purple.opacity(0.6), radius: 20)
                        
                        Text("What’s on your mind?")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        if !contextMemory.isEmpty {
                            Text("Konteksti aktiivinen (\(contextMemory.count) merkkiä)")
                                .font(.caption)
                                .foregroundStyle(.cyan.opacity(0.7))
                        }
                    }
                } else {
                    // Chat scroll
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(messages) { msg in
                                    messageBubble(msg)
                                }
                                
                                // Streaming bubble
                                if !streamingResponse.isEmpty {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(streamingResponse)
                                                .padding(14)
                                                .background(Color.white.opacity(0.08))
                                                .foregroundStyle(.white)
                                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                                .frame(maxWidth: 280, alignment: .leading)
                                            
                                            if isResponding {
                                                ProgressView()
                                                    .scaleEffect(0.7)
                                                    .tint(.cyan)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)
                        }
                        .onChange(of: messages.count) { _ in scrollToBottom(proxy: proxy) }
                        .onChange(of: streamingResponse) { _ in scrollToBottom(proxy: proxy) }
                    }
                }
                
                Spacer()
                
                // Gemini-style pill input
                HStack(spacing: 10) {
                    Button {
                        // future: attachments or clear
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    
                    TextField("Ask AFM", text: $inputText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .font(.body)
                        .padding(.horizontal, 6)
                        .submitLabel(.send)
                        .onSubmit {
                            if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                                sendMessage()
                            }
                        }
                    
                    Button {
                        // voice placeholder
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 34, height: 34)
                    }
                    
                    Button {
                        if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                            sendMessage()
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle( (inputText.isEmpty || isResponding) ? .gray : .white )
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isResponding)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.65))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            
            // Error overlay
            if showError {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Color.red.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showContextSheet) {
            contextSheet
        }
        .onAppear {
            checkAvailability()
        }
    }
    
    private func messageBubble(_ msg: Message) -> some View {
        HStack {
            if msg.isUser {
                Spacer(minLength: 40)
                Text(msg.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.1))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .frame(maxWidth: 260, alignment: .trailing)
            } else {
                Text(msg.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.07))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .frame(maxWidth: 260, alignment: .leading)
                Spacer(minLength: 40)
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = messages.last {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
    
    private func checkAvailability() {
        if !isModelAvailable {
            errorMessage = "Apple Intelligence ei ole päällä tai laitteesi ei tue sitä. Asetukset → Apple Intelligence"
            showError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { showError = false }
        }
    }
    
    // MARK: - Send message with streaming
    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isModelAvailable, !isResponding else { return }
        
        let userMsg = Message(text: trimmed, isUser: true)
        messages.append(userMsg)
        inputText = ""
        isResponding = true
        streamingResponse = ""
        
        // Build prompt with context if exists
        var prompt = trimmed
        if !contextMemory.isEmpty {
            prompt = """
            Edellinen konteksti keskusteluista:
            \(contextMemory)
            
            Nykyinen viesti käyttäjältä:
            \(trimmed)
            
            Vastaa luonnollisesti ja hyödyllisesti ottaen kontekstin huomioon.
            """
        }
        
        Task {
            do {
                let stream = chatSession.streamResponse(to: prompt)
                
                for try await partial in stream {
                    await MainActor.run {
                        streamingResponse = partial.content
                    }
                }
                
                // Finalize: move streaming to permanent message
                await MainActor.run {
                    if !streamingResponse.isEmpty {
                        let finalMsg = Message(text: streamingResponse, isUser: false)
                        messages.append(finalMsg)
                    }
                    streamingResponse = ""
                    isResponding = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Virhe vastauksessa: \(error.localizedDescription)"
                    showError = true
                    streamingResponse = ""
                    isResponding = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                    showError = false
                }
            }
        }
    }
    
    // MARK: - Separate context creation process (erillinen AFM prosessi)
    private func createContextAndReset() {
        guard !messages.isEmpty else { return }
        
        isCreatingContext = true
        
        // Build full transcript for context maker
        let transcript = messages.map { msg in
            "\(msg.isUser ? "Käyttäjä" : "AFM"): \(msg.text)"
        }.joined(separator: "\n")
        
        let contextPrompt = """
        Olet kontekstin luoja. Lue koko keskustelu alla ja tiivistä se lyhyeksi, selkeäksi kontekstiksi tulevia keskusteluja varten.
        Sisällytä vain tärkeimmät faktat, käyttäjän mieltymykset, aiheet ja avainpisteet. Pidä lyhyenä (max 400 merkkiä).
        
        Keskustelu:
        \(transcript)
        
        Tiivistelmä kontekstiksi:
        """
        
        Task {
            do {
                let response = try await contextSession.respond(to: contextPrompt)
                let newContext = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                
                await MainActor.run {
                    if !newContext.isEmpty {
                        // Append or replace context (simple append for now)
                        if contextMemory.isEmpty {
                            contextMemory = newContext
                        } else {
                            contextMemory += "\n\n--- Uusi konteksti ---\n" + newContext
                        }
                    }
                    // Reset chat for new conversation
                    messages = []
                    streamingResponse = ""
                    isCreatingContext = false
                    
                    // Optional toast
                    errorMessage = "Konteksti luotu ja tallennettu. Uusi keskustelu valmis."
                    showError = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    showError = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Kontekstin luonti epäonnistui: \(error.localizedDescription)"
                    showError = true
                    isCreatingContext = false
                }
            }
        }
    }
    
    private var contextSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Nykyinen kontekstimuisti")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    
                    if contextMemory.isEmpty {
                        Text("Ei vielä kontekstia. Keskustele ja paina 'Luo konteksti & uusi' luodaksesi.")
                            .foregroundStyle(.white.opacity(0.6))
                    } else {
                        Text(contextMemory)
                            .font(.body)
                            .foregroundStyle(.white)
                            .padding()
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    Button("Tyhjennä konteksti") {
                        contextMemory = ""
                        showContextSheet = false
                    }
                    .foregroundStyle(.red)
                    .padding(.top)
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("AFM Konteksti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sulje") { showContextSheet = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
