// Commands.kt: words the app handles itself, before the game's answers.

/**
 * Words the app handles itself, before the game's answers: "stop" and "cancel" pause the game, the way Alexa's Stop
 * and Cancel end a skill (docs/MAP_FORMAT.md, "App commands"). "Pause" is not one: Leaning Tower of Pizza hears it
 * as a mishear of "false".
 */
public enum AppCommands {
    private static let pause: Set<String> = ["stop", "cancel"]

    public static func isPause(_ said: String) -> Bool { pause.contains(SpokenText.normalise(said)) }
}
