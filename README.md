# Student Loan Management Smart Contract

A comprehensive Clarity smart contract for managing student loans on the Stacks blockchain with automated interest calculation, payment tracking, and collateral management.

## Overview

This smart contract provides a complete solution for student loan management, enabling loan creation, payment processing, interest calculation, and loan lifecycle management in a decentralized manner.

## Features

### Core Functionality
- **Loan Creation**: Create loans with customizable terms, interest rates, and collateral requirements
- **Payment Processing**: Process loan payments with automatic interest/principal allocation
- **Interest Calculation**: Real-time compound interest calculation based on blockchain blocks
- **Multi-loan Support**: Each borrower can hold up to 10 active loans simultaneously

### Advanced Features
- **Payment History**: Track up to 50 payments per loan with detailed breakdowns
- **Collateral Management**: Support for collateral-backed loans with liquidation capabilities
- **Overdue Detection**: Automatic identification of overdue loans
- **Contract Analytics**: Comprehensive statistics and reporting

## Technical Specifications

### Constants
```clarity
MIN_LOAN_AMOUNT: 1,000,000 µSTX (1 STX)
MAX_LOAN_AMOUNT: 1,000,000,000,000 µSTX (1M STX)
MAX_INTEREST_RATE: 2000 basis points (20%)
MIN_TERM_BLOCKS: 52,560 blocks (~1 year)
MAX_TERM_BLOCKS: 1,577,880 blocks (~30 years)
```

### Data Structures

#### Loan Structure
```clarity
{
    borrower: principal,
    original-amount: uint,
    current-balance: uint,
    interest-rate: uint,        // basis points (100 = 1%)
    issue-block: uint,
    term-blocks: uint,
    monthly-payment: uint,
    payments-made: uint,
    total-payments: uint,
    is-active: bool,
    collateral: uint
}
```

#### Payment Record
```clarity
{
    block: uint,
    amount: uint,
    interest: uint,
    principal: uint
}
```

## Function Reference

### Read-Only Functions

#### `get-loan(loan-id: uint)`
Retrieves loan details for a specific loan ID.
- **Returns**: `(optional loan-data)` or `none` if not found

#### `get-borrower-loans(borrower: principal)`
Gets all loan IDs for a specific borrower.
- **Returns**: `(list 10 uint)` of loan IDs

#### `get-contract-stats()`
Returns contract-wide statistics.
- **Returns**: 
  ```clarity
  {
      total-loans: uint,
      total-issued: uint,
      total-repaid: uint,
      contract-balance: uint
  }
  ```

#### `calculate-current-balance(loan-id: uint)`
Calculates current loan balance including accrued interest.
- **Returns**: `(response uint uint)` with current balance

#### `is-loan-overdue(loan-id: uint)`
Checks if a loan is overdue based on payment schedule.
- **Returns**: `(response bool uint)` indicating overdue status

### Public Functions

#### `create-loan(borrower: principal, amount: uint, interest-rate: uint, term-blocks: uint, collateral: uint)`
Creates a new loan (Owner only).
- **Parameters**:
  - `borrower`: Loan recipient
  - `amount`: Loan amount in µSTX
  - `interest-rate`: Annual rate in basis points
  - `term-blocks`: Loan duration in blocks
  - `collateral`: Collateral amount in µSTX
- **Returns**: `(response uint uint)` with new loan ID

#### `make-payment(loan-id: uint, payment-amount: uint)`
Process a loan payment.
- **Parameters**:
  - `loan-id`: Target loan ID
  - `payment-amount`: Payment in µSTX
- **Returns**: `(response {payment-id: uint, remaining-balance: uint} uint)`

#### `approve-lender(lender: principal)`
Approve a lender for future operations (Owner only).
- **Returns**: `(response bool uint)`

#### `fund-contract(amount: uint)`
Add funds to the contract for loan disbursement.
- **Returns**: `(response uint uint)` with funded amount

#### `liquidate-loan(loan-id: uint)`
Liquidate an overdue loan (Owner only).
- **Returns**: `(response uint uint)` with collateral amount

#### `emergency-withdraw(amount: uint)`
Emergency fund withdrawal (Owner only).
- **Returns**: `(response uint uint)` with withdrawn amount

## Usage Examples

### Creating a Loan
```clarity
;; Create a 10 STX loan at 5% interest for 2 years with 2 STX collateral
(contract-call? .student-loan create-loan 
    'ST1BORROWER123456789 
    u10000000      ;; 10 STX
    u500           ;; 5% (500 basis points)
    u105120        ;; ~2 years in blocks
    u2000000)      ;; 2 STX collateral
```

### Making a Payment
```clarity
;; Make a 1 STX payment on loan #1
(contract-call? .student-loan make-payment u1 u1000000)
```

### Checking Loan Status
```clarity
;; Get loan details
(contract-call? .student-loan get-loan u1)

;; Check if overdue
(contract-call? .student-loan is-loan-overdue u1)
```

## Security Features

### Input Validation
- All user inputs are validated and bounded within safe ranges
- Protection against integer overflow/underflow
- Principal address validation

### Access Control
- Owner-only functions for loan creation and management
- Borrower-only payment processing
- Approved lender system

### Error Handling
- Comprehensive error codes for all failure scenarios
- Safe arithmetic operations
- Proper bounds checking

## Error Codes

| Code | Description |
|------|-------------|
| u100 | Not authorized |
| u101 | Loan not found |
| u102 | Invalid amount |
| u103 | Loan already exists |
| u104 | Insufficient balance |
| u105 | Loan already paid |
| u106 | Invalid interest rate |
| u107 | Payment too large |
| u108 | Invalid term |
| u109 | Invalid collateral |
| u110 | Invalid loan ID |
| u111 | Invalid principal |

## Deployment

1. Deploy the contract to Stacks blockchain
2. Fund the contract using `fund-contract`
3. Start creating loans with `create-loan`
4. Borrowers can make payments with `make-payment`

