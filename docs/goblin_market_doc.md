# A Social Betting & Execution Layer Complementary to Polymarket

## 1. Executive Summary

We are building a **complementary product to Polymarket**, not a competing prediction market.

Polymarket already solves:

- Market creation
- Liquidity
- Oracle resolution
- Settlement

Our product focuses on:

- Social betting primitives
- Copy & bet mechanics
- Peer-to-peer ('1v1') betting
- BNB Chain-native UX using BUSD

In simple terms:

**Polymarket provides the markets.**

**We provide social execution, copy strategies, and new betting formats on top of them.**

## 2. Why This Product Exists

Despite Polymarket's success, there are gaps:

- No **copy betting**
- No **social execution**
- No **1v1 custom betting**
- No **BNB Chain or BUSD support**
- Complex UX for non-crypto-native users

These are **product gaps**, not liquidity gaps.

Our product fills those gaps **without rebuilding a prediction market**.

## 3. What We Are NOT Building (Important)

To avoid confusion:

- ✗ We are NOT building a new prediction market
- ✗ We are NOT creating or resolving markets
- ✗ We are NOT competing on liquidity
- ✗ We are NOT replacing Polymarket

Instead, we **reference Polymarket as a source of truth**.

## 4. Technical Reality: Polymarket Constraints

This section explains _why_ certain design decisions are necessary.

### Polymarket Today

- Runs on **Polygon**
- Uses **USDC**
- Has fixed smart contracts
- Does not support:
  - **BUSD**

- BNB Chain
- External execution hooks

### Implication

**It is technically impossible to natively place BUSD bets on Polymarket.**

Any product claiming otherwise is either:

- Custodial
- Bridging-heavy
- Or misleading

## 5. Our Core Technical Decision

### Key Question

How can users bet in **BUSD on BNB Chain** while leveraging Polymarket markets?

### Answer

We use a **synthetic exposure model**, not direct execution.

## 6. The Chosen Architecture: Synthetic Polymarket-Referenced Bets

### Concept

Our protocol creates **bets that track Polymarket outcomes**, rather than executing trades directly on Polymarket.

This is similar to:

- How perpetuals track spot prices
- How prediction derivatives work
- How copy trading platforms mirror strategies

### Step-by-Step Flow

#### ① Market Indexing

We index Polymarket markets in a **read-only** manner:

- Market ID
- Outcomes
- Odds
- Resolution conditions

No interaction with Polymarket contracts.

---

#### ② User Bets in BUSD (BNB Chain)

- Users bet using **BUSD**
- Funds are locked in our smart contracts
- Bets reference a Polymarket market ID

---

#### **③ Odds Snapshot**

At bet time:

- Polymarket odds are recorded
- Entry probability is fixed
- Bet terms are immutable

---

#### **④ Resolution & Settlement**

When Polymarket resolves:

- We read the outcome
- Our protocol settles bets
- Winners are paid in **BUSD**

Polymarket acts as an **external resolution reference**, not a counterparty.

---

## **7. Why This Model Was Chosen**

### **What This Makes Possible**

- ✓ BUSD support
- ✓ Native BNB Chain UX
- ✓ Copy & bet functionality
- ✓ 1v1 betting
- ✓ Fast settlement
- ✓ No bridging
- ✓ No dependency on Polymarket permissions

---

### What This Avoids

- ✕ Complex cross-chain execution
- ✕ Custodial risk
- ✕ Liquidity competition
- ✕ Oracle management
- ✕ UX friction

---

## 8. Copy & Bet (Core Differentiator)

### What It Is

Users can:

- Follow top bettors
- Automatically mirror their bets
- Set risk limits:
  - Fixed amount
  - Percentage of bankroll
  - Max exposure per market

### How It Works Technically

- Leader places a synthetic bet
- Followers' bets are auto-executed
- All settlement happens in BUSD

This feature **cannot be built natively on Polymarket today** — it is our edge.

---

## 9. 1v1 Betting (Existing MVP)

### What It Enables

- Direct bets between two users
- Custom stake sizes
- Custom odds (optional)
- Resolution based on Polymarket outcome

### Why It Matters

- Social
- Viral
- Community-driven
- Not liquidity-dependent

This feature is already functional and integrates naturally with the synthetic model.

---

## 10. What Is Technically Impossible (By Design)

For clarity with investors:

- ✗ Direct BUSD execution on Polymarket
- ✗ Native Polymarket copy trading
- ✗ BNB Chain settlement via Polymarket
- ✗ Modifying Polymarket odds or markets

Any roadmap claiming this is **not realistic today**.

---

## 11. Risk & Responsibility

### Protocol Risk

Because we offer synthetic exposure:

- The protocol is the settlement engine
- Risk is managed via:
  - Exposure caps
  - Max bet sizes
  - Fee buffers
  - Optional hedging later

### Regulatory Considerations

- No market creation
- No oracle control
- Non-custodial smart contracts
- Geo-blocking where required
- DAO-first transition path

---

## 12. Future Evolution (Optional, Not Required)

Later stages may include:

- Partial hedging on Polymarket
- Advanced copy-bet analytics
- DAO governance
- API access for power users

These are **extensions**, not dependencies.

---

## 13. Final Positioning

**We are building the social execution layer for prediction markets.**

Polymarket provides truth and liquidity.

We provide distribution, social signal, and new betting primitives.

---

## 14. Why This Is a Rational Bet

- We build **on top of success**, not against it
- We avoid liquidity wars
- We move fast
- We own the UX and social layer
- We stay technically honest

### Architecture 1 — Synthetic Exposure

This is the **cleanest, fastest, and most realistic** way to use BUSD.

#### Mental model

We are not placing bets on Polymarket.

We are creating a derivative that tracks Polymarket outcomes.

Think:

**“Perpetuals track spot price — they don’t own the asset.”**

---

#### Flow

##### **1** Market ingestion

- Your backend indexes Polymarket:
  - Market ID
  - Outcomes
  - Odds / prices
  - Resolution condition
- This data is read-only

---

##### **2** User bets in BUSD (BNB Chain)

- User selects:
  - Market
  - Outcome (YES / NO)
  - Amount in BUSD
- Funds go into your smart contract vault

---

##### **③** Odds locking

At bet time:

- You snapshot Polymarket odds
- Convert odds → implied probability

Store:

market_id  
outcome  
odds_at_entry  
amount  
user_address

●

##### --- **④** Settlement (critical)

When Polymarket resolves:

- You read:
  - Resolved: YES / NO
- Your contract:
  - Pays winners from the pool
  - Losers' funds redistribute

No Polymarket interaction happens on-chain.

---

#### Payout math (simple example)

- Polymarket odds:
  - YES = 0.40
  - NO = 0.60

User bets:

- 100 BUSD on YES

Payout formula:

`payout = bet_amount / odds`

`payout = 100 / 0.40 = 250 BUSD (if YES wins)`

You can:

- Take protocol fee (e.g. 1-3%)
- Adjust spreads to manage risk

---

#### Who carries risk?

We do.

Because:

- We are the counterparty
- We must ensure:
  - Pool solvency
  - Proper risk limits
  - Max exposure caps

#### --- Pros

- ✓ Native BNB Chain
- ✓ BUSD works perfectly
- ✓ Fast UX
- ✓ Easy copy-bet
- ✓ No bridging
- ✓ No Polymarket permissions needed

#### Cons

- ✗ We are a betting protocol
- ✗ Risk management required
- ✗ Regulatory exposure higher

---

#### How copy & bet fits here (perfectly)

Copy-bet becomes trivial:

- Leader places a synthetic bet
- Followers auto-place the same bet
- All in BUSD
- Same settlement logic

This is the correct architecture for copy betting.

---

### Architecture 2 — Real Execution via Bridging (NOT recommended early)

This is what people _think_ they want — but it's painful.

---

#### Flow

1. User deposits BUSD on BNB Chain
2. You bridge:

- BUSD → USDC
- BNB Chain → Polygon

3. Execute trade on Polymarket

#### 4. On resolution:

- Claim USDC
- Bridge back
- Convert to BUSD
- Withdraw

---

##### Problems (serious)

- ✗ Multi-bridge latency
- ✗ High fees
- ✗ UX disaster
- ✗ Failure-prone
- ✗ Copy-bet scaling nightmare
- ✗ Custodial implications

Unless you are managing millions, this is not worth it.

---

### Architecture 3 — Hybrid Model (future)

This is what mature platforms do later.

---

#### How it works

- Retail users
  - Synthetic exposure (Architecture 1)
- High-volume / whale users
  - Real Polymarket execution

Your backend:

- Aggregates exposure
- Hedges selectively on Polymarket

This lets you:

- Reduce protocol risk
- Maintain BUSD UX
- Capture arbitrage opportunities

---

#### Where 1v1 betting fits (cleanly)

Your existing 1v1 MVP fits perfectly with Architecture 1.

#### Example

- Alice: YES
- Bob: NO
- 100 BUSD each
- Outcome references Polymarket

Your protocol:

- Holds 200 BUSD
- Pays winner
- Takes fee

This is orthogonal to Polymarket liquidity — very strong.

---

##### Smart contract architecture (BNB Chain)

#### Core contracts

- `Vault.sol`
  - Holds BUSD

- Locks funds
- MarketRegistry.sol
  - Maps Polymarket market IDs
  - Stores resolution source
- BetEngine.sol
  - Synthetic odds logic
  - Copy-bet execution
  - 1v1 logic
- SettlementOracle.sol
  - Reads Polymarket resolution
  - Writes final outcome

Oracle can be:

- Manual (admin) early
- Chainlink / UMA later

---

#### Compliance angle (important)

Synthetic model changes your legal posture:

We are:

- **X** Not a market creator
- **X** Not an oracle

- **X** Not Polymarket

But you are:

- A betting protocol
- A payout engine

Mitigations:

- Geo-block
- Non-custodial
- Explicit terms
- DAO transition path
