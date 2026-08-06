// Project names come from the microbial world — one word, sometimes two.
//
// Port of the naming scheme in the web app's src/projects.ts. The lists and
// the order of the random draws both matter: change either and a seeded
// stream stops matching the web.

public enum ProjectNames {
    public static let creatures = [
        "Amoeba", "Volvox", "Paramecium", "Euglena", "Rotifer", "Diatom",
        "Vorticella", "Stentor", "Spirogyra", "Tardigrade", "Chlorella",
        "Bacillus", "Vibrio", "Spirulina", "Rhizopus", "Micrococcus", "Nostoc",
        "Anabaena", "Daphnia", "Ciliate", "Archaea", "Mycelium", "Plankton",
        "Coccus", "Protist", "Desmid", "Hydra", "Copepod", "Radiolaria",
        "Foraminifera", "Streptococcus", "Lactobacillus", "Cyanobacteria",
        "Dinoflagellate", "Choanoflagellate", "Slime Mould", "Blue Green",
    ]

    public static let modifiers = [
        "Motile", "Wild", "Blooming", "Silent", "Drifting", "Warm", "Deep",
        "Salt", "Night", "Split", "Twin", "Slow", "Bright", "Soft", "Rogue",
    ]

    public static func random(using random: RandomSource) -> String {
        let creature = creatures[random.index(creatures.count)]
        if random.chance(0.45) {
            return "\(modifiers[random.index(modifiers.count)]) \(creature)"
        }
        return creature
    }
}
