//
//  CorrespondenceGamesView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 8/26/20.
//

import SwiftUI
import Combine

struct CorrespondenceGamesView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var ogs: OGSService
    @State var currentGame: Game
    @State var pendingMove: Move? = nil
    @State var pendingPosition: BoardPosition? = nil
    @State var ogsRequestCancellable: AnyCancellable?
    @State var activeGames: [Game] = []
    @State var activeGameByOGSID: [Int: Game] = [:]
    @State var stoneRemovalSelectedPoints = Set<[Int]>()

    @State var showingPassAlert = false
    @State var showingResumeFromStoneRemovalAlert = false

    func updateActiveGameList() {
        self.activeGames = []
        for game in ogs.sortedActiveCorrespondenceGames {
            self.activeGames.append(game)
            if let ogsID = game.ogsID {
                self.activeGameByOGSID[ogsID] = game
            }
        }
    }

    func submitMove(move: Move) {
        self.ogsRequestCancellable = ogs.submitMove(move: move, forGame: currentGame)
            .zip(currentGame.$currentPosition.setFailureType(to: Error.self))
            .sink(receiveCompletion: { _ in
                DispatchQueue.main.async {
                    self.ogsRequestCancellable = nil
                }
            }, receiveValue: { _ in
                DispatchQueue.main.async {
                    self.pendingMove = nil
                    self.pendingPosition = nil
                    self.ogsRequestCancellable = nil
                }
            })
    }
    
    func toggleRemovedStones(stones: Set<[Int]>) {
        self.ogsRequestCancellable = ogs.toggleRemovedStones(stones: stones, forGame: currentGame)
            .zip(currentGame.currentPosition.$removedStones.setFailureType(to: Error.self))
            .sink(receiveCompletion: { _ in
                DispatchQueue.main.async {
                    self.ogsRequestCancellable = nil
                }
            }, receiveValue: { _ in
                DispatchQueue.main.async {
                    self.stoneRemovalSelectedPoints.removeAll()
                    self.ogsRequestCancellable = nil
                }
            })
    }
    
    func acceptRemovedStones() {
        ogs.acceptRemovedStone(game: currentGame)
        self.ogsRequestCancellable = currentGame.$removedStonesAccepted.sink(receiveValue: { _ in
            self.ogsRequestCancellable = nil
        })
    }
    
    func resumeGameFromStoneRemoval() {
        ogs.resumeGameFromStoneRemoval(game: currentGame)
        self.ogsRequestCancellable = currentGame.$gamePhase.sink(receiveValue: { _ in
            self.ogsRequestCancellable = nil
        })
    }
    
    func goToNextGame() {
        if let currentIndex = activeGames.firstIndex(where: { game in game.ID == currentGame.ID }) {
            for game in activeGames[currentIndex.advanced(by: 1)..<activeGames.endIndex] + activeGames[activeGames.startIndex..<currentIndex] {
                if game.clock?.currentPlayerId == ogs.user?.id {
                    withAnimation {
                        currentGame = game
                    }
                    break
                }
            }
        }
    }

    var isUserPlaying: Bool {
        guard let user = ogs.user else {
            return false
        }
        return user.id == currentGame.gameData?.blackPlayerId || user.id == currentGame.gameData?.whitePlayerId
    }
    
    var isUserTurn: Bool {
        guard isUserPlaying else {
            return false
        }

        guard currentGame.gamePhase == .play else {
            return false
        }
        
        return (currentGame.clock?.currentPlayer == .black && ogs.user?.id == currentGame.gameData?.blackPlayerId)
            || (currentGame.clock?.currentPlayer == .white && ogs.user?.id == currentGame.gameData?.whitePlayerId)
    }
    
    var undoable: Bool {
        guard isUserPlaying else {
            return false
        }
        
        guard currentGame.gamePhase == .play && currentGame.gameData?.outcome == nil else {
            return false
        }
        
        return !isUserTurn && currentGame.undoRequested == nil && currentGame.currentPosition.lastMoveNumber > 0
    }
    
    var undoacceptable: Bool {
        guard let undoRequested = currentGame.undoRequested else {
            return false
        }
        return isUserTurn && undoRequested == currentGame.currentPosition.lastMoveNumber
    }
    
    var defaultStatus: String {
        if let currentPlayer = currentGame.clock?.currentPlayer {
            return "\(currentPlayer == .black ? "Black" : "White") to move"
        } else {
            return ""
        }
    }
    
    var status: String {
        if let outcome = currentGame.gameData?.outcome {
            if currentGame.gameData?.winner == currentGame.gameData?.blackPlayerId {
                return "Black wins by \(outcome)"
            } else {
                return "White wins by \(outcome)"
            }
        } else {
            if currentGame.gamePhase == .stoneRemoval {
                return "Stone Removal Phase"
            }
            if currentGame.undoRequested != nil {
                return "Undo requested"
            }
            if isUserPlaying {
                if isUserTurn {
                    if case .pass = currentGame.currentPosition.lastMove {
                        return "Opponent passed"
                    } else {
                        return "Your move"
                    }
                } else {
                    return "Waiting for opponent"
                }
            } else {
                return defaultStatus
            }
        }
    }
    
    var statusText: some View {
        Group {
            if undoacceptable {
                Menu {
                    Button(action: { ogs.acceptUndo(game: currentGame, moveNumber: currentGame.undoRequested!) }) {
                        Label("Accept undo", systemImage: "arrow.uturn.left")
                    }
                }
                label: {
                    Text("\(status) ▾").font(Font.title2.bold())
                }
            } else {
                Text(status).font(Font.title2.bold())
            }
        }
    }
    
    var actionButtons: some View {
        HStack(alignment: .firstTextBaseline) {
            if ogsRequestCancellable == nil {
                let isUserTurnToPlay = currentGame.gamePhase == .play && isUserTurn
                let userNeedsToAcceptStoneRemoval = currentGame.gamePhase == .stoneRemoval
                    && currentGame.removedStonesAccepted[userColor(in: currentGame)] != currentGame.currentPosition.removedStones
                if isUserTurnToPlay {
                    if let pendingMove = pendingMove {
                        Button(action: { submitMove(move: pendingMove)}) {
                            Text("Submit move")
                        }
                    } else {
                        Button(action: { self.showingPassAlert = true }) {
                            Text("Pass")
                        }
                    }
                } else if userNeedsToAcceptStoneRemoval {
                    Button(action: { acceptRemovedStones() }) {
                        Text("Accept")
                    }
                } else {
                    if ogs.sortedActiveCorrespondenceGamesOnUserTurn.count > 0 {
                        Button(action: goToNextGame) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("Next")
                                Text("(\(ogs.sortedActiveCorrespondenceGamesOnUserTurn.count))")
                                    .font(Font.caption2.bold())
                            }
                        }
                    }
                }
            } else {
                ProgressView().alignmentGuide(.firstTextBaseline, computeValue: { viewDimension in
                    viewDimension.height
                })
            }
            Menu {
                if currentGame.gamePhase == .play {
                    Button(action: { ogs.requestUndo(game: currentGame) }) {
                        Label("Request undo", systemImage: "arrow.uturn.left")
                    }.disabled(!undoable)
                } else if currentGame.gamePhase == .stoneRemoval {
                    Button(action: { self.showingResumeFromStoneRemovalAlert = true }) {
                        Label("Resume game", systemImage: "play")
                    }
                }
                Button(action: { UIApplication.shared.open(currentGame.ogsURL!) }) {
                    Label("Open in browser", systemImage: "safari")
                }
                Button(action: {}) {
                    Label("Resign", systemImage: "flag").accentColor(.red)
                }
            }
            label: {
                Label("More actions", systemImage: "ellipsis.circle.fill").labelStyle(IconOnlyLabelStyle())
            }
            .padding(.leading)
            
            // Putting these inside conditional views above does not seem to work well
            Rectangle().frame(width: 0, height: 0)
                .alert(isPresented: $showingResumeFromStoneRemovalAlert) {
                    Alert(
                        title: Text("Are you sure you want to resume the game?"),
                        message: nil,
                        primaryButton: .destructive(Text("Resume")) {
                            self.resumeGameFromStoneRemoval()
                        },
                        secondaryButton: .cancel(Text("Cancel"))
                    )
                }
            Rectangle().frame(width: 0, height: 0)
                .alert(isPresented: $showingPassAlert) {
                    Alert(
                        title: Text("Are you sure you want to pass?"),
                        message: nil,
                        primaryButton: .destructive(Text("Pass")) {
                            self.submitMove(move: .pass)
                        },
                        secondaryButton: .cancel(Text("Cancel"))
                    )
                }

        }
    }
    
    var controlRow: some View {
        HStack(alignment: .firstTextBaseline) {
            statusText
            Spacer()
            actionButtons
        }
    }
    
    var boardView: some View {
        BoardView(
            boardPosition: currentGame.currentPosition,
            playable: isUserTurn,
            stoneRemovable: isUserPlaying && currentGame.gamePhase == .stoneRemoval,
            newMove: $pendingMove,
            newPosition: $pendingPosition,
            stoneRemovalSelectedPoints: $stoneRemovalSelectedPoints
        )
    }
    
    func userColor(in game: Game) -> StoneColor {
        return ogs.user?.id == game.blackId ? .black : .white
    }
    
    var compactBody: some View {
        GeometryReader { geometry -> AnyView in
            print("Geometry \(geometry.size)")
            
            let boardSize: CGFloat = min(geometry.size.width, geometry.size.height)
            let controlRowHeight: CGFloat = NSString(string: status).boundingRect(with: geometry.size, attributes: [.font: UIFont.preferredFont(forTextStyle: .title2)], context: nil).size.height
            let usableHeight: CGFloat = geometry.size.height
            let playerInfoHeight: CGFloat = 64 + 64 - 10 + 15 * 2
            let spacing: CGFloat = 10.0
            let remainingHeight: CGFloat = usableHeight - boardSize - controlRowHeight - playerInfoHeight - (spacing * 2)
            let showsActiveGamesCarousel = remainingHeight >= 140 || (remainingHeight + geometry.safeAreaInsets.bottom * 2 / 3 >= 140)
            let reducedPlayerInfoVerticalPadding = (showsActiveGamesCarousel && remainingHeight <= 150) || remainingHeight < 0

            return AnyView(erasing: VStack(alignment: .leading) {
//                Text("\(usableHeight) \(controlRowHeight) \(remainingHeight)")
                PlayersBannerView(game: currentGame, topLeftPlayerColor: self.userColor(in: currentGame).opponentColor(), reduceVerticalPadding: reducedPlayerInfoVerticalPadding)
                Spacer(minLength: spacing)
                controlRow
                    .padding(.horizontal)
                Spacer(minLength: spacing)
                boardView.frame(width: boardSize, height: boardSize)
                if showsActiveGamesCarousel {
                    ActiveCorrespondenceGamesCarousel(currentGame: $currentGame, activeGames: activeGames)
                }
            })
        }
    }
    
    var regularBody: some View {
        GeometryReader { geometry -> AnyView in
            let width = geometry.size.width
            let height = geometry.size.height - 140 - 15 * 2
            let boardSizeHorizontal = min(height, width - 300 - 15 * 3)
            let boardSizeVertical = min(width - 15 * 2, height - 80 - 15 * 2 - 15 * 4)
            var horizontal = true
            var boardSizeLimit = boardSizeHorizontal
            let playerInfoWidth = width - boardSizeHorizontal - 15 * 3
            var playerIconsOffset: CGFloat = 25
            if playerInfoWidth > 400 {
                playerIconsOffset = -10
            }
            if boardSizeVertical > boardSizeHorizontal {
                horizontal = false
                boardSizeLimit = boardSizeVertical
            }
            if boardSizeLimit < 0 {
                return AnyView(EmptyView())
            }
            return AnyView(erasing: VStack(spacing: 0) {
                ActiveCorrespondenceGamesCarousel(currentGame: $currentGame, activeGames: activeGames)
                Spacer(minLength: 0)
                if horizontal {
                    HStack(alignment: .top, spacing: 15) {
                        VStack(alignment: .trailing) {
                            PlayersBannerView(game: currentGame, topLeftPlayerColor: self.userColor(in: currentGame).opponentColor(), playerIconSize: 80, playerIconsOffset: playerIconsOffset, showsPlayersName: true)
                                .frame(minWidth: 300)
                            Spacer().frame(maxHeight: 15)
                            VStack(alignment: .trailing) {
                                statusText
                                actionButtons
//                                Text("\(width) \(height)")
//                                Text("\(boardSizeLimit)")
                            }
                            Spacer()
                        }
                        boardView.frame(width: boardSizeLimit, height: boardSizeLimit)
                    }
                    .padding()
                    .frame(height: boardSizeLimit + 15 * 2)
                } else {
                    VStack(alignment: .center, spacing: 0) {
                        PlayersBannerView(game: currentGame, topLeftPlayerColor: self.userColor(in: currentGame).opponentColor(), playerIconSize: 80, playerIconsOffset: -80, showsPlayersName: true)
                        Spacer(minLength: 15)
                        controlRow
                        Spacer(minLength: 15)
                        boardView.frame(width: boardSizeLimit, height: boardSizeLimit)
                    }
                    .padding()
                    .frame(maxWidth: boardSizeLimit + 15 * 2)
                }
                Spacer(minLength: 0)
            })
        }
    }
    
    var body: some View {
        var compactLayout = true
        #if os(iOS)
        compactLayout = horizontalSizeClass == .compact
        #endif
        let userColor: StoneColor = currentGame.blackId == ogs.user?.id ? .black : .white
        let players = currentGame.gameData!.players
        let opponent = userColor == .black ? players.white : players.black
        let opponentRank = userColor == .black ? currentGame.whiteFormattedRank : currentGame.blackFormattedRank

        return Group {
            if compactLayout {
                compactBody
            } else {
                regularBody
            }
        }
        .background(
            colorScheme == .dark ?
                Color(UIColor.systemGray5).edgesIgnoringSafeArea(.bottom) :
                Color.white.edgesIgnoringSafeArea(.bottom)
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {}) {
                    Label("Active games carousel", systemImage: "gearshape.2")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("vs \(opponent.username) [\(opponentRank)]")
        .onAppear {
            updateActiveGameList()
            for game in activeGames {
                ogs.updateDetailsOfConnectedGame(game: game)
            }
        }
        .onChange(of: currentGame) { _ in
            self.pendingMove = nil
            self.pendingPosition = nil
        }
        .onChange(of: stoneRemovalSelectedPoints) { selectedPoints in
            self.toggleRemovedStones(stones: selectedPoints)
        }
        .onReceive(ogs.$sortedActiveCorrespondenceGames) { sortedActiveGames in
            
        }
    }
}

struct CorrespondenceGamesView_Previews: PreviewProvider {
    static var previews: some View {
        let games = [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2, TestData.Ongoing19x19wBot3]
        return NavigationView {
            CorrespondenceGamesView(currentGame: games[0], activeGames: games)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .environmentObject(
            OGSService.previewInstance(
                user: OGSUser(username: "kata-bot", id: 592684),
                activeGames: games
            )
        )
//        .previewLayout(.fixed(width: 750, height: 704))
//        .previewLayout(.fixed(width: 1024, height: 768))
//        .previewLayout(.fixed(width: 768, height: 1024))
//        .previewLayout(.fixed(width: 375, height: 812))
//        .previewLayout(.fixed(width: 568, height: 320))
        .colorScheme(.dark)
    }
}
