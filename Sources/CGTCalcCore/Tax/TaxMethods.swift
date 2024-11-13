//
//  TaxMethods.swift
//  cgtcalc
//
//  Created by Matt Galloway on 08/06/2020.
//

import Foundation

class TaxMethods {
  static func roundedGain(_ gain: Decimal) -> Decimal {
    return gain.rounded(to: 0, roundingMode: .down)
  }
    static func roundedExpense(_ gain: Decimal) -> Decimal {
      return gain.rounded(to: 0, roundingMode: .up)
    }
}
