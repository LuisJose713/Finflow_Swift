import Foundation

@main
struct COPInputChecks {
    static func main() {
        precondition(COPInput.normalize("25000") == "25000")
        precondition(COPInput.display("25000", padDecimals: true) == "25.000,00")
        precondition(COPInput.normalize("$ 1.250.000,50 COP") == "1250000.50")
        precondition(COPInput.normalize("0,25") == "0.25")
        precondition(COPInput.normalize("12.34") == "12.34")
        precondition(COPInput.normalize("12.345", previous: "12.34") == nil)
        precondition(COPInput.normalize("12,345", previous: "12.34") == nil)
        precondition(COPInput.normalize("1.250") == "1250")
        precondition(COPInput.normalize("1.23.456") == nil)
        precondition(COPInput.normalize("1000000000000,01") == nil)
        precondition(COPInput.normalize("-25") == nil)
        precondition(COPInput.normalize("") == "")
        precondition(COPInput.display("1250.5", padDecimals: true) == "1.250,50")
        precondition(COPInput.display("1250.", padDecimals: false) == "1.250,")
        precondition(COPInput.display("0", padDecimals: true) == "0,00")
        print("COP input contract verified: units, grouping, cents and boundaries.")
    }
}
