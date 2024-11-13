//
//  TextPresenter.swift
//  cgtcalc
//
//  Created by Matt Galloway on 08/06/2020.
//

import Foundation

public class TextPresenter: Presenter {
  private let result: CalculatorResult
  private let dateFormatter: DateFormatter

  public required init(result: CalculatorResult) {
    self.result = result
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    dateFormatter.dateFormat = "dd/MM/yyyy"
    self.dateFormatter = dateFormatter
  }

  public func process() throws -> PresenterResult {
    var output = ""
    output += "# SUMMARY\n\n"
    output += self.summaryTable()

    output += "\n\n"

    output += "# TAX YEAR DETAILS\n\n"
    output += self.detailsOutput()

    output += "\n"

    output += "# TRANSACTIONS\n\n"
    output += self.transactionsTable()

    output += "\n\n"

    output += "# ASSET EVENTS\n\n"
    output += self.assetEventsTable()

    return .string(output)
  }

  private static func formattedCurrency(_ amount: Decimal, _ places:Int = 2) -> String {
    return "£\(amount.rounded(to: places).string)"
  }

  private func summaryTable() -> String {
    let rows = self.result.taxYearSummaries
      .reduce(into: [[String]]()) { output, summary in
        let row = [
          summary.taxYear.string,
          String(summary.numberOfDisposals),
          TextPresenter.formattedCurrency(summary.proceeds),
          TextPresenter.formattedCurrency(summary.totalAllowableCosts),
          TextPresenter.formattedCurrency(summary.totalGainsBeforeLosses),
          TextPresenter.formattedCurrency(summary.totalLosses),
          TextPresenter.formattedCurrency(summary.gain),
          TextPresenter.formattedCurrency(summary.exemption),
          TextPresenter.formattedCurrency(summary.carryForwardLoss),
          TextPresenter.formattedCurrency(summary.taxableGain),
          TextPresenter.formattedCurrency(summary.basicRateTax),
          TextPresenter.formattedCurrency(summary.higherRateTax)
        ]
        output.append(row)
      }

    let headerRow = [
      "Tax year",
      "No. Disposals",
      "Proceeds",
      "Allowable Costs",
      "Gain b/f Losses",
      "Losses",
      "Net Gain",
      "Exemption",
      "Loss carry",
      "Taxable gain",
      "Tax (basic)",
      "Tax (higher)"
    ]
    let initialMaxWidths = headerRow.map { $0.count }
    let maxWidths = rows.reduce(into: initialMaxWidths) { result, row in
      for i in 0 ..< result.count {
        result[i] = max(result[i], row[i].count)
      }
    }

    let builder = { (input: [String]) -> String in
      var out: [String] = []
      for (i, column) in input.enumerated() {
        out.append(column.padding(toLength: maxWidths[i], withPad: " ", startingAt: 0))
      }
      return out.joined(separator: "   ")
    }

    let header = builder(headerRow)
    var output = header + "\n"
    output += String(repeating: "=", count: header.count) + "\n"
    for row in rows {
      output += builder(row) + "\n"
    }
    return output
  }

  private func detailsOutput() -> String {
    return self.result.taxYearSummaries
      .reduce(into: "") { output, summary in
        output += "## TAX YEAR \(summary.taxYear)\n\n"

        var count = 1
        summary.disposalResults
          .forEach { disposalResult in
            output += "\(count)) \(disposalResult.disposal.kind.description) \(disposalResult.disposal.amount) shares"
            output += " of \(disposalResult.disposal.asset) at \(TextPresenter.formattedCurrency(disposalResult.disposalUnitPrice,5)) per share"
            output += " on \(self.dateFormatter.string(from: disposalResult.disposal.date))"
            output += " for "
            output += disposalResult.loss.isZero ? disposalResult.gain.isZero ? "NO NET GAIN\n" : 
            "GAIN of \(TextPresenter.formattedCurrency(disposalResult.gain))\n" :
            "LOSS of \(TextPresenter.formattedCurrency(disposalResult.loss))\n"
            output += "\nMatches with holdings(s):\n"
            disposalResult.disposalMatches.forEach { disposalMatch in
              output += "  • \(TextPresenter.disposalMatchDetails(disposalMatch, dateFormatter: self.dateFormatter))\n"
            }
            output += "\nCalculation: \(TextPresenter.disposalResultCalculationString(disposalResult))\n"
              output += "\n________________________________________\n\n"
            count += 1
          }
      }
  }

  private func transactionsTable() -> String {
    guard self.result.input.transactions.count > 0 else {
      return "NONE"
    }

    return self.result.input.transactions.reduce(into: "") { result, transaction in
      result += "\(dateFormatter.string(from: transaction.date)) \(transaction.kind.description) \(transaction.amount) of \(transaction.asset)"
      if transaction.kind != .Gift { result += " at £\(transaction.price) with £\(transaction.expenses) expenses"}
      result += "\n"
    }
  }

  private func assetEventsTable() -> String {
    guard self.result.input.assetEvents.count > 0 else {
      return "NONE"
    }

    return self.result.input.assetEvents.reduce(into: "") { result, assetEvent in
      result += "\(dateFormatter.string(from: assetEvent.date)) \(assetEvent.asset) "
      switch assetEvent.kind {
      case .CapitalReturn(let amount, let value):
        result += "CAPITAL RETURN on \(amount) for \(TextPresenter.formattedCurrency(value))"
      case .Dividend(let amount, let value):
        result += "DIVIDEND on \(amount) for \(TextPresenter.formattedCurrency(value))"
      case .Split(let multiplier):
        result += "SPLIT by \(multiplier)"
      case .Unsplit(let multiplier):
        result += "UNSPLIT by \(multiplier)"
      }
      result += "\n"
    }
  }
}

extension TextPresenter {
  private static func disposalMatchDetails(_ disposalMatch: DisposalMatch, dateFormatter: DateFormatter) -> String {
    switch disposalMatch.kind {
    case .SameDay(let acquisition):
      var output =
        "SAME DAY: \(acquisition.amount) shares bought on \(dateFormatter.string(from: acquisition.date)) at \(formattedCurrency(acquisition.price))"
      if !acquisition.offset.isZero {
        output += " with offset of £\(acquisition.offset)"
      }
      return output
    case .BedAndBreakfast(let acquisition):
      var output =
        "BED & BREAKFAST: \(acquisition.amount) shares bought on \(dateFormatter.string(from: acquisition.date)) at \(formattedCurrency(acquisition.price))"
      if !acquisition.offset.isZero {
        output += " with offset of £\(acquisition.offset)"
      }
      if disposalMatch.restructureMultiplier != Decimal(1) {
        output += " with restructure multiplier \(disposalMatch.restructureMultiplier)"
      }
      return output
    case .Section104(let amountAtDisposal, let costBasis):
      return "SECTION 104: \(amountAtDisposal) shares at cost basis of \(formattedCurrency(costBasis,5))"
    }
  }

  private static func disposalResultCalculationString(_ disposalResult: CalculatorResult.DisposalResult) -> String {
      
    var output = "\n • PROCEEDS:\n\t\(disposalResult.disposal.amount) shares x \(formattedCurrency(disposalResult.disposalUnitPrice)) = \(formattedCurrency(disposalResult.grossProceeds))\n • COSTS:\n\tDisposal fees: \(formattedCurrency(disposalResult.disposal.expenses))\n"

    var disposalMatchesStrings: [String] = []
    for disposalMatch in disposalResult.disposalMatches {
                
      switch disposalMatch.kind {
      case .SameDay(let acquisition), .BedAndBreakfast(let acquisition):
          var output = "\tAcquisition cost: (\(acquisition.amount) shares x \(acquisition.price)) + \(formattedCurrency(acquisition.expenses)) fees = \(formattedCurrency(disposalMatch.acquisitionCostIncludingExpenses))"
        if !acquisition.offset.isZero {
          output += " + \(acquisition.offset)"
        }
        //output += ")"
        disposalMatchesStrings.append(output)
      case .Section104(_, let costBasis):
          disposalMatchesStrings.append("\tAcquisition cost: \(disposalMatch.disposal.amount) shares x \(formattedCurrency(costBasis,5)) = \(formattedCurrency(disposalMatch.acquisitionCostIncludingExpenses))")
      }
    }
    output += disposalMatchesStrings.joined(separator: "\n")
    output += "\n\nTotal proceeds = \(formattedCurrency(disposalResult.grossProceeds))"
    output += "\nTotal costs    = \(formattedCurrency(disposalResult.allowableCosts))"
    output += "\n\nTotal gain     = \(formattedCurrency(disposalResult.gain))"
    output += "\nTotal loss     = \(formattedCurrency(disposalResult.loss))"
    
    return output
  }
}
