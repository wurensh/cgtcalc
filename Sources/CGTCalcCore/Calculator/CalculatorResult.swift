//
//  CalculatorResult.swift
//  cgtcalc
//
//  Created by Matt Galloway on 08/06/2020.
//

import Foundation

public struct CalculatorResult {
  let input: CalculatorInput
  let taxYearSummaries: [TaxYearSummary]

  struct DisposalResult {
    let disposal: Transaction
    private let _gain: Decimal
    let disposalMatches: [DisposalMatch]
    
    init(disposal: Transaction, disposalMatches: [DisposalMatch]) {
      self.disposal = disposal
      self.disposalMatches = disposalMatches
      self._gain = TaxMethods.roundedGain(disposalMatches.reduce(Decimal.zero) {$0 + $1.gain})
    }

    /// Returns costs associated with this disposal, namely the acquisition cost (plus any acquisition expenses) and any
    /// fees/expenses associated with the disposal. Used for Tax Return summary
    var allowableCosts: Decimal { disposalMatches.reduce(disposal.expenses) { $0 + $1.acquisitionCostIncludingExpenses} }
    
    /// Returns the gross proceeds of the disposal (the amount *before* any expenses/fees or other costs have been deducted
    /// This is used for the Tax Return 'disposable proceeds' box
    var grossProceeds: Decimal { disposalMatches.reduce(Decimal.zero) { $0 + $1.grossDisposalProceeds} }
    
    /// Returns the net gain for this disposal. If a loss this returns zero
    var gain: Decimal { _gain.isSignMinus ? Decimal.zero : _gain }
    
    /// Returns the net loss for this disposal. If no loss then returns zero
    var loss: Decimal {_gain.isSignMinus ? abs(_gain) : Decimal.zero}
    
    /// Returns true if this disposal related to a transfer/gift of assets.
    var isGift:Bool { disposal.kind == .Gift }
    
    /// Returns the unit price of the disposal. This value is normally specified in the transactions file, however for
    /// gift disposals the price needs to be derived from the transferring assets in order to have a net-zero "gain".
    var disposalUnitPrice: Decimal { isGift ? grossProceeds / disposal.amount : disposal.price }
  }

  struct TaxYearSummary {
    let taxYear: TaxYear
    let gain: Decimal
    let proceeds: Decimal
    let numberOfDisposals: Int
    let totalAllowableCosts: Decimal
    let totalGainsBeforeLosses: Decimal
    let totalLosses: Decimal
    let exemption: Decimal
    let carryForwardLoss: Decimal
    let taxableGain: Decimal
    let basicRateTax: Decimal
    let higherRateTax: Decimal
    let disposalResults: [DisposalResult]
  }

  init(input: CalculatorInput, disposalMatches: [DisposalMatch]) throws {
    self.input = input

    var carryForwardLoss = Decimal.zero
    self.taxYearSummaries = try Dictionary(grouping: disposalMatches, by: \.taxYear)
      .sorted { $0.key < $1.key }
      .map { taxYear, disposalMatches in
        let disposalMatchesByDisposal = Dictionary(grouping: disposalMatches, by: \.disposal.transaction)

        var totalGain = Decimal.zero
        var numberOfDisposals = 0
        var totalLosses = Decimal.zero
        var totalGainsBeforeLosses = Decimal.zero
        var totalProceeds = Decimal.zero
        var totalAllowableCosts = Decimal.zero

        let disposalResults =
          disposalMatchesByDisposal.map { disposal, disposalMatches -> DisposalResult in
            let disposalResult = DisposalResult(disposal: disposal, disposalMatches: disposalMatches)
            // Update tax year running totals
            numberOfDisposals += 1
            totalGain += disposalResult.gain - disposalResult.loss
            totalGainsBeforeLosses += disposalResult.gain
            totalLosses += disposalResult.loss
            totalProceeds += disposalResult.grossProceeds
            totalAllowableCosts += disposalResult.allowableCosts

            return disposalResult
          }
          .sorted {
            if $0.disposal.date == $1.disposal.date {
              return $0.disposal.asset < $1.disposal.asset
            }
            return $0.disposal.date < $1.disposal.date
          }

        guard let taxYearRates = TaxYear.rates[taxYear] else {
          throw CalculatorError.InternalError("Missing tax year rates for \(taxYear)")
        }

        let taxableGain: Decimal
        let gainAboveExemption = max(totalGain - taxYearRates.exemption, Decimal.zero)
        if !gainAboveExemption.isZero {
          let lossUsed = min(gainAboveExemption, carryForwardLoss)
          taxableGain = gainAboveExemption - lossUsed
          carryForwardLoss -= lossUsed
        } else {
          taxableGain = Decimal.zero
          if totalGain.isSignMinus {
            carryForwardLoss -= totalGain
          }
        }
        let basicRateTax = TaxMethods.roundedGain(taxableGain * taxYearRates.basicRate * 0.01)
        let higherRateTax = TaxMethods.roundedGain(taxableGain * taxYearRates.higherRate * 0.01)

        return TaxYearSummary(
          taxYear: taxYear,
          gain: totalGain,
          proceeds: TaxMethods.roundedGain(totalProceeds),
          numberOfDisposals: numberOfDisposals,
          totalAllowableCosts: TaxMethods.roundedExpense(totalAllowableCosts),
          totalGainsBeforeLosses: totalGainsBeforeLosses,
          totalLosses: totalLosses,
          exemption: taxYearRates.exemption,
          carryForwardLoss: carryForwardLoss,
          taxableGain: taxableGain,
          basicRateTax: basicRateTax,
          higherRateTax: higherRateTax,
          disposalResults: disposalResults)
      }
  }
}
