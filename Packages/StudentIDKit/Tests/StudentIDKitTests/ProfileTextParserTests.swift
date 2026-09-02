import CoreGraphics
import Foundation
import Testing
@testable import StudentIDKit

/// The field heuristics, exercised directly on recognized lines. Keeping these
/// separate from OCR means every layout variation is cheap and deterministic to
/// test; only one case has to go all the way through Vision.
@Suite struct ProfileTextParserTests {

    private let pageHeight: CGFloat = 2868

    /// The real page's shape, with invented values.
    private func profileLines(name: String = "Riley Vasquez") -> [TextLine] {
        [
            line("Student Profile", x: 48, y: 300, width: 380, height: 46),
            line("0 Items in Cart", x: 48, y: 420, width: 260, height: 34),
            line("$0.00", x: 340, y: 420, width: 120, height: 34),
            line(name, x: 520, y: 540, width: 560, height: 58),
            line("Enrollments", x: 520, y: 630, width: 220, height: 36),
            line("26-27 Adlai E Stevenson High S", x: 520, y: 690, width: 640, height: 36),
            line("Grade 12", x: 520, y: 746, width: 200, height: 36),
            line("26-27 Adlai E Stevenson Summer", x: 520, y: 810, width: 660, height: 36),
            line("Grade 12", x: 520, y: 866, width: 200, height: 36),
            line("ENDED", x: 520, y: 922, width: 160, height: 32),
            line("Student Number", x: 520, y: 1020, width: 300, height: 36),
            line("59435", x: 520, y: 1080, width: 180, height: 40),
            line("Student Identification Barcode", x: 48, y: 1200, width: 620, height: 34),
        ]
    }

    @Test func readsTheNumberBelowItsLabel() {
        #expect(ProfileTextParser.printedStudentNumber(in: profileLines()) == "59435")
    }

    @Test func readsTheNumberWhenRecognitionMergesItWithTheLabel() {
        let lines = [
            line("Student Number 59435", x: 520, y: 1020, width: 460, height: 36),
        ]
        #expect(ProfileTextParser.printedStudentNumber(in: lines) == "59435")
    }

    @Test func ignoresNumbersThatAreNotStudentNumbers() {
        let lines = [
            line("Student Number", x: 520, y: 1020, width: 300, height: 36),
            line("12", x: 520, y: 1080, width: 60, height: 40),
            line("847555", x: 520, y: 1140, width: 200, height: 40),
        ]
        // Two digits is too short to be an ID; the next plausible run wins.
        #expect(ProfileTextParser.printedStudentNumber(in: lines) == "847555")
    }

    @Test(arguments: ["Student Number 123 59435", "Student Number 123456789 59435"])
    func skipsInvalidDigitRunsOnTheSameLine(text: String) {
        #expect(ProfileTextParser.printedStudentNumber(in: [line(text, x: 0, y: 0)]) == "59435")
    }

    @Test func usesTheBarcodeToDisambiguateNumbersOnTheSameLine() {
        let lines = [line("Student Number 2026 59435", x: 0, y: 0)]
        #expect(ProfileTextParser.printedStudentNumber(in: lines, matching: ["59435"]) == "59435")
        #expect(ProfileTextParser.printedStudentNumber(in: lines, matching: ["2026"]) == "2026")
        #expect(ProfileTextParser.printedStudentNumber(in: lines, matching: ["11111"]) == "2026")
    }

    @Test func considersEveryDigitRunBelowTheLabel() {
        let lines = [line("Student Number", x: 0, y: 0),
                     line("123 2026 59435", x: 0, y: 60)]
        #expect(ProfileTextParser.printedStudentNumber(in: lines, matching: ["59435"]) == "59435")
    }

    @Test func readsTheNameSittingAboveTheEnrollmentsLabel() {
        let name = ProfileTextParser.fullName(in: profileLines(), imageHeight: pageHeight)
        #expect(name == "Riley Vasquez")
    }

    @Test func neverMistakesPageChromeForAName() {
        // Drop the name; nothing left above the label is a person.
        var lines = profileLines()
        lines.removeAll { $0.text == "Riley Vasquez" }
        #expect(ProfileTextParser.fullName(in: lines, imageHeight: pageHeight) == nil)
    }

    @Test func rejectsSchoolNamesPricesAndLabelsAsNames() {
        for candidate in ["Student Profile", "Enrollments", "$0.00", "Grade 12",
                          "26-27 Adlai E Stevenson High S", "Today's Schedule",
                          "ENDED", "Teacher: Anderson, Katie", "3012",
                          "Adlai E. Stevenson", "Stevenson High S", "Stevenson Summer",
                          "Summer School", "Items in Cart", "Room", "Term"] {
            #expect(!ProfileTextParser.looksLikePersonName(candidate),
                    "\"\(candidate)\" was accepted as a name")
        }
    }

    @Test func acceptsTheShapesRealNamesTake() {
        for candidate in ["Riley Vasquez", "Mary-Kate O'Neill", "Jo Ann St. Clair",
                          "Ana Sofía Ramírez Cruz", "Summer Chen", "Riley Stevenson",
                          "Dean Grade", "April Teacher", "Summer-Rose Chen",
                          "Adlai Chen", "Carter Day", "Summerfield Chen"] {
            #expect(ProfileTextParser.looksLikePersonName(candidate),
                    "\"\(candidate)\" was rejected as a name")
        }
    }

    @Test(arguments: ["Summer Chen", "Riley Stevenson", "Dean Grade"])
    func keepsTheStudentsNameInsteadOfFallingBackToAnotherLine(name: String) {
        #expect(ProfileTextParser.fullName(in: profileLines(name: name), imageHeight: pageHeight) == name)
    }

    @Test func stitchesANameSplitAcrossTwoObservations() {
        var lines = profileLines()
        lines.removeAll { $0.text == "Riley Vasquez" }
        lines.append(line("Riley", x: 520, y: 540, width: 200, height: 58))
        lines.append(line("Vasquez", x: 740, y: 540, width: 260, height: 58))
        #expect(ProfileTextParser.fullName(in: lines, imageHeight: pageHeight) == "Riley Vasquez")
    }

    @Test func fallsBackToTheLargestTextWhenTheLabelIsMissing() {
        var lines = profileLines()
        lines.removeAll { $0.normalized == "enrollments" }
        // The name is the biggest type on the upper half of that page.
        #expect(ProfileTextParser.fullName(in: lines, imageHeight: pageHeight) == "Riley Vasquez")
    }

    @Test func readsTheGradeOfTheEnrollmentThatIsStillRunning() {
        #expect(ProfileTextParser.gradeLevel(in: profileLines()) == 12)
    }

    @Test func skipsTheGradeBelongingToAnEndedEnrollment() {
        let lines = [
            line("Enrollments", x: 520, y: 630, width: 220, height: 36),
            line("26-27 Adlai E Stevenson Summer", x: 520, y: 690, width: 660, height: 36),
            line("Grade 11", x: 520, y: 746, width: 200, height: 36),
            line("ENDED", x: 520, y: 800, width: 160, height: 32),
            line("26-27 Adlai E Stevenson High S", x: 520, y: 880, width: 640, height: 36),
            line("Grade 12", x: 520, y: 936, width: 200, height: 36),
        ]
        #expect(ProfileTextParser.gradeLevel(in: lines) == 12)
    }

    @Test func readsTheSchoolYearFromTheEnrollmentLine() {
        #expect(ProfileTextParser.schoolYearStart(in: profileLines()) == 2026)
    }

    @Test func ignoresNumberPairsThatAreNotConsecutiveYears() {
        let lines = [line("Room 30-12", x: 0, y: 0, width: 200, height: 30),
                     line("25-26 Adlai E Stevenson High S", x: 0, y: 60, width: 600, height: 30)]
        #expect(ProfileTextParser.schoolYearStart(in: lines) == 2025)
    }

    @Test func findsAConsecutiveYearPairAfterADateOnTheSameLine() {
        let lines = [line("08/26 26-27 Adlai E Stevenson High S", x: 0, y: 0)]
        #expect(ProfileTextParser.schoolYearStart(in: lines) == 2026)
    }

    @Test func readingOrderRemainsTransitiveAcrossDriftingBaselines() {
        let lines = [line("Grade 12", x: 100, y: 0, height: 40),
                     line("Grade 11", x: 50, y: 16, height: 40),
                     line("Grade 10", x: 10, y: 32, height: 40)]
        for a in lines {
            #expect(!ProfileTextParser.readingOrder(a, a))
            for b in lines where ProfileTextParser.readingOrder(a, b) {
                #expect(!ProfileTextParser.readingOrder(b, a))
                for c in lines where ProfileTextParser.readingOrder(b, c) {
                    #expect(ProfileTextParser.readingOrder(a, c))
                }
            }
        }
        for order in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
            #expect(ProfileTextParser.gradeLevel(in: order.map { lines[$0] }) == 12)
        }
    }

    @Test func recognizesTheProfilePageByItsLabels() {
        #expect(ProfileTextParser.looksLikeProfilePage(profileLines()))
        #expect(!ProfileTextParser.looksLikeProfilePage([
            line("Gate C14", x: 0, y: 0, width: 200, height: 30),
            line("Boarding pass", x: 0, y: 60, width: 300, height: 30),
        ]))
    }
}
