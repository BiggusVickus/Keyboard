import Foundation

/// de or het.
public enum DutchGender: String, Codable, Sendable {
    case de
    case het

    /// "deze" for de-words, "dit" for het-words.
    public var demonstrative: String { self == .de ? "deze" : "dit" }
}

/// Why a noun has its gender. Used to give a useful explanation.
public enum DutchGenderReason: Equatable, Sendable {
    /// It is in the word list: it just has to be learned.
    case listed
    /// Ends in -je: diminutives are always het.
    case diminutive
    /// A suffix that decides the gender, e.g. -heid → de.
    case suffix(String)
    /// A compound: the last part decides, e.g. ziekenhuis → huis → het.
    case compound(lastPart: String)
}

/// A small built-in de/het dictionary for common nouns, plus the rules that are always true.
/// Words that can be both (het/de idee) or that are often used as adjectives or adverbs
/// (morgen, fout, tijd) are left out on purpose, so the check never flags a correct sentence.
public enum DutchNouns {
    public static func gender(of noun: String) -> (gender: DutchGender, reason: DutchGenderReason)? {
        let word = noun.lowercased()
        guard word.count >= 2, !notNouns.contains(word) else { return nil }

        if hetWords.contains(word) { return (.het, .listed) }
        if deWords.contains(word) { return (.de, .listed) }

        // Diminutives: huisje, meisje, kopje, boompje, koninkje, kipje.
        if word.count >= 4, word.hasSuffix("je") { return (.het, .diminutive) }

        for suffix in deSuffixes where word.count > suffix.count + 1 && word.hasSuffix(suffix) {
            return (.de, .suffix(suffix))
        }
        for suffix in hetSuffixes where word.count > suffix.count + 1 && word.hasSuffix(suffix) {
            return (.het, .suffix(suffix))
        }

        // Compounds take the gender of their last part: voetbalveld → veld → het.
        guard !adjectiveEndings.contains(where: { word.hasSuffix($0) }) else { return nil }
        for split in 3..<max(3, word.count - 3) {
            let lastPart = String(word.dropFirst(split))
            if hetWords.contains(lastPart) { return (.het, .compound(lastPart: lastPart)) }
            if deWords.contains(lastPart) { return (.de, .compound(lastPart: lastPart)) }
        }
        return nil
    }

    /// Words the rules below would wrongly treat as nouns (oranje isn't a diminutive).
    static let notNouns: Set<String> = ["oranje", "beige", "roze"]

    static let deSuffixes = ["heid", "ing", "tie", "sie", "teit", "iek", "tuur", "erij", "arij", "ster", "nis"]
    static let hetSuffixes = ["isme", "ment", "um"]
    /// Words with these endings are usually adjectives, so they are never treated as compounds.
    static let adjectiveEndings = ["lijk", "ig", "isch", "baar", "loos", "rijk", "zaam", "en", "end", "ief", "eel", "aal"]

    // MARK: - Word lists

    static func words(_ list: String) -> Set<String> {
        Set(list.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    static let hetWords = words("""
        aanrecht aantal accent adres advies akkoord alfabet ambacht antwoord apparaat appartement argument
        artikel atelier avondeten avontuur bad balkon bed bedrag bedrijf beeld been begin begrip behang
        belang beleid bericht beroep besluit bestand bestuur bewijs bezit bezoek bier bijwoord blad bloed
        boek bord bos brood buitenland bureau cadeau café centrum cijfer college concert contact contract
        dagboek dak dal dekbed dessert diner ding diploma document doel dorp dossier drama duits ei eiland
        eind einde engels enkelvoud eten examen experiment feest feit fietspad formulier frans fruit gas
        gat gebak gebed gebied gebit gebouw gebruik gedicht gedrag geduld geheim geheugen geld geloof
        geluid geluk gemak gemeentehuis gerecht gereedschap geschenk geslacht gesprek getal gevaar geval
        gevecht gevoel gevolg gewas gewicht gezicht gezin glas gordijn goud gras hart heden hek hemd hert
        hoofd hoofdgerecht hoofdstuk horloge hotel hout huis huisdier huiswerk huwelijk ijs ijzer inkomen
        insect instrument internet interview italiaans jaar kabinet kader kalf kamp kantoor kapitaal
        karakter kasteel kenmerk kerkhof kilo kind klimaat klooster konijn koninkrijk koor kostuum kruid
        kruis kruispunt kuiken kwartier laken lam land landschap lawaai leger leven lichaam lid lidwoord
        lied lijf lint lokaal loket loon lot meervoud menu mes metaal meubel middel midden model moment
        monster monument museum naamwoord nadeel nederlands nest netwerk nieuws niveau noorden nummer
        object onderwerp onderwijs onderzoek ongeluk ontbijt ontwerp oog oor oordeel oosten orgaan overhemd
        overleg overzicht paard pak pakket paleis papier paradijs park parlement paspoort pensioen
        percentage perron personeel plafond plan plein plezier portret postkantoor potlood principe
        probleem proces product programma project publiek raadsel raam rapport recept recht record register
        restaurant resultaat rijbewijs risico ritme salaris sap schaap schema scherm schip seizoen sieraad
        signaal slot spaans spek spel spook spoor staal stadhuis stadion standpunt station stoplicht strand
        stuk stuur succes systeem tapijt tarief team teken tempo terras terrein theater thema tijdperk
        tijdschrift toestel toetsenbord toilet toneel touw uitzicht uur vak varken vat vel veld venster
        verbod verdrag verdriet verhaal verkeer verleden verlies verlof vermogen verschil verstand
        vertrouwen vervoer vervolg verzoek vest vlees vliegtuig vliegveld voedsel voertuig volk vonnis
        voorbeeld voordeel voorgerecht voorjaar voorstel voorwerp voorzetsel vuur wachtwoord wapen
        warenhuis water weekend weiland werk werkwoord westen wiel wonder woord woordenboek zaad zand zeil
        ziekenhuis zilver zout zuiden zwaard zweet zwembad
        """)

    static let deWords = words("""
        aap aardappel aardbei adem afspraak afstand akker angst app appel arm arts auto avond baan baas
        baby badkamer bank beer beker berg betaling bladzijde bloem boer boerderij boom boot boter brief
        bril broek broer brug buik bus buurman buurt buurvrouw chef cirkel club collega computer cultuur
        das datum deur dief dienst dijk discussie docent dokter doos douche droom eend emmer energie
        envelop ervaring euro familie fiets film fles foto gang garage gedachte gemeente geschiedenis
        gevangenis gezondheid gracht grens griep groente groep hand haven hemel herfst heuvel hoed hoek
        hond honger hulp jas jongen jurk kaart kaas kamer kans kant kast kat keel kelder kerk kerst keuken
        keuze kip klant klas kleur koe koelkast koffie koorts kop krant kust laptop leerling lente leraar
        lerares les lift lijn lijst lunch maaltijd maan maand maat man markt melk mening metro minuut
        moeder molen mond motor muis munt muur muziek naam nacht natuur neus nicht ochtend oma ooievaar oom
        oorlog oorzaak opa opdracht oplossing oven pagina pan pen persoon pet pijn pizza plaats plant plek
        politie pop portemonnee positie post prijs provincie puzzel radio regel regen reis rekening relatie
        richting rijst rivier rok rug ruimte saus schoen school sfeer sinaasappel slaapkamer slang sleutel
        sloot sneeuw snelweg soep sok sport stad stem ster stoel storm straat stroom student suiker
        supermarkt taak taal taart tafel tand tante taxi tekst telefoon televisie thee tocht toekomst toets
        tomaat tong tram trap trein tuin ui universiteit vader vakantie verdieping vergadering verjaardag
        vis vloer voet vogel vork vraag vriend vriendin vriendschap vrouw vrucht wandeling wasmachine
        website wedstrijd week wereld wet wijk wijn wind winkel winter wolk woonkamer wortel zaak zak zee
        ziekte zin zolder zomer zon zorg zus zuster
        """)
}
