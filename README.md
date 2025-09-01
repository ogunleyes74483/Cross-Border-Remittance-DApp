# 🌍 Cross-Border Remittance DApp

> 💸 A transparent and secure remittance platform built on Stacks blockchain for seamless cross-border money transfers

## 🚀 Overview

The Cross-Border Remittance DApp enables families and individuals to send money across borders using STX tokens with automated fee logic, delivery timing, and beneficiary management. Built with Clarity smart contracts, it provides transparency, security, and cost-effectiveness for international remittances.

## ✨ Features

- 💰 **Secure Transfers**: Send money to beneficiaries with blockchain security
- ⏰ **Timed Delivery**: Set custom delivery times for transfers
- 🔒 **Escrow System**: Funds held securely until delivery time
- 💳 **Low Fees**: Transparent fee structure (2.5% platform fee)
- 📊 **Transfer Tracking**: Monitor all sent and received transfers
- ❌ **Cancellation**: Cancel transfers before delivery time
- 🏦 **Wallet Management**: Deposit and withdraw STX tokens

## 🛠️ Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- [Stacks Wallet](https://www.hiro.so/wallet) for testing

### Installation

```bash
git clone <repository-url>
cd cross-border-remittance-dapp
clarinet check
```

### Testing

```bash
clarinet test
```

### Deployment

```bash
clarinet deploy --testnet
```

## 📖 Usage Guide

### 1. 💳 Deposit Funds

Before sending transfers, deposit STX tokens into your account:

```clarity
(contract-call? .cross-border deposit u10000000) ;; Deposit 10 STX
```

### 2. 📤 Create Transfer

Send money to a beneficiary with custom delivery time:

```clarity
(contract-call? .cross-border create-transfer 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 u5000000 u144) ;; Send 5 STX, deliver in 144 blocks (~24 hours)
```

### 3. 📥 Claim Transfer

Beneficiaries can claim transfers after delivery time:

```clarity
(contract-call? .cross-border claim-transfer u1) ;; Claim transfer ID 1
```

### 4. ❌ Cancel Transfer

Senders can cancel transfers before delivery time:

```clarity
(contract-call? .cross-border cancel-transfer u1) ;; Cancel transfer ID 1
```

### 5. 💸 Withdraw Funds

Withdraw your balance back to your wallet:

```clarity
(contract-call? .cross-border withdraw u5000000) ;; Withdraw 5 STX
```

## 🔍 Read-Only Functions

### Check Transfer Details
```clarity
(contract-call? .cross-border get-transfer u1)
```

### Check Your Balance
```clarity
(contract-call? .cross-border get-user-balance tx-sender)
```

### View Your Transfers
```clarity
(contract-call? .cross-border get-sender-transfers tx-sender)
(contract-call? .cross-border get-beneficiary-transfers tx-sender)
```

### Calculate Fees
```clarity
(contract-call? .cross-border calculate-fee u1000000) ;; Fee for 1 STX
```

## 💼 Business Logic

### Fee Structure
- Platform fee: 2.5% (250 basis points)
- Minimum transfer: 1 STX
- Maximum transfer: 100 STX

### Transfer States
- **pending**: Transfer created, waiting for delivery time
- **claimed**: Beneficiary has claimed the transfer
- **cancelled**: Sender cancelled before delivery

### Security Features
- ✅ Funds held in escrow until delivery
- ✅ Only beneficiaries can claim transfers
- ✅ Only senders can cancel before delivery
- ✅ Time-locked delivery system
- ✅ Balance validation for all operations

## 🏗️ Contract Architecture

### Data Structures
- `transfers`: Main transfer records
- `user-balances`: User STX balances
- `sender-transfers`: Transfer history for senders
- `beneficiary-transfers`: Transfer history for beneficiaries

### Key Functions
- `create-transfer`: Initiate new remittance
- `claim-transfer`: Beneficiary claims funds
- `cancel-transfer`: Sender cancels transfer
- `deposit/withdraw`: Wallet management

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License.

## 🆘 Support

For support and questions:
- Create an issue in this repository
- Join our community discussions

---

Made with ❤️ for global financial inclusion 🌍
```

**Git Commit Message:**
```
feat: implement cross-border remittance MVP with escrow and timed delivery
```

**GitHub Pull Request Title:**
```
🌍 Add Cross-Border Remittance DApp MVP
```

**GitHub Pull Request Description:**
```
## 🚀 Cross-Border Remittance DApp MVP

This PR introduces a complete MVP for a cross-border remittance platform built on Stacks blockchain.

### ✨ Features Added
- 💰 Secure STX token transfers with escrow system
- ⏰ Timed delivery mechanism for transfers
- 🔒 Beneficiary-only claim system
- ❌ Transfer cancellation before delivery
- 💳 Deposit/withdrawal wallet management
- 📊 Transfer tracking and history
- 🏦 Platform fee collection (2.5%)

### 🛠️ Technical Implementation
- Complete Clarity smart contract (150+ lines)
- Comprehensive error handling
- Read-only functions for data queries
- Admin functions for platform management
- Secure fund escrow with time locks

### 📖 Documentation
- Detailed README with usage instructions
- Code examples for all major functions
- Business logic explanation
- Security features overview

### 🧪 Ready for Testing
- All functions implemented and tested
- Error cases handled
- Ready for Clarinet testing suite

This MVP provides a solid foundation for cross-border remittances with transparency, security, and cost-effectiveness.

