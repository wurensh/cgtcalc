//
//  DisposalMatch.swift
//  cgtcalc
//
//  Created by Matt Galloway on 08/06/2020.
//

import Foundation

class DisposalMatch {
  let kind: Kind
  let disposal: TransactionToMatch
  let restructureMultiplier: Decimal

  var asset: String {
    return self.disposal.asset
  }

  var date: Date {
    return self.disposal.date
  }

  var taxYear: TaxYear {
    return TaxYear(containingDate: self.disposal.date)
  }

  var isGift: Bool { self.disposal.transaction.kind == .Gift }
  
  enum Kind {
    /**
     * Same day match.
     * Parameter is the buy transaction that this disposal was matched against.
     */
    case SameDay(TransactionToMatch)

    /**
     * Bed-and-breakfast match (buy within 30 days of a sale).
     * Parameter is the buy transaction that this disposal was matched against.
     */
    case BedAndBreakfast(TransactionToMatch)

    /**
     * Section 104 holding match (pool of shares not matched on any other rule).
     * First parameter is the amount of holding, second parameter is the cost basis.
     */
    case Section104(Decimal, Decimal)
  }

  init(kind: Kind, disposal: TransactionToMatch, restructureMultiplier: Decimal) {
    self.kind = kind
    self.disposal = disposal
    self.restructureMultiplier = restructureMultiplier
  }

  var gain: Decimal {
    return grossDisposalProceeds - self.disposal.expenses - acquisitionCostIncludingExpenses
  }
  
  var grossDisposalProceeds: Decimal {
    // If this disposal represents a gift then the gain should net to zero
    // so the proceeds should equal the acquisition costs. Note that for gifts it's assumed the
    // disposalExpenses are always zero (this is enforced by the parsing of GIFT transactions)
    return isGift ? acquisitionCostIncludingExpenses : self.disposal.value
  }
  
  var acquisitionCostIncludingExpenses: Decimal {
    switch self.kind {
    case .SameDay(let acquisition), .BedAndBreakfast(let acquisition):
      return acquisition.value + acquisition.expenses
    case .Section104(_, let costBasis):
      return (self.disposal.amount * costBasis)
    }
  }
}

extension DisposalMatch: CustomStringConvertible {
  var description: String {
    return "<\(String(describing: type(of: self))): kind=\(self.kind), asset=\(self.asset), date=\(self.date), taxYear=\(self.taxYear), disposal=\(self.disposal), gain=\(self.gain), restructureMultiplier=\(self.restructureMultiplier)>"
  }
}
