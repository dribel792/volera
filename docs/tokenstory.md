# Anduin Token Story
*Draft v1 — February 2026*

---

## Executive Summary

Anduin is prime brokerage infrastructure: multi-broker netting, settlement, and lending on Base L2. The question is not whether to do a token — it's whether a token **adds real economic function** or is just a fundraising mechanism dressed up in utility language.

The honest answer: most token rationales for infrastructure protocols are weak. Governance tokens on B2B infra are nearly worthless. "Own L2" tokens are engineering overkill for the current scale. The one angle that holds up is a **staking/insurance token with real yield** — token holders underwrite the protocol's risk, earn protocol fees in return, and create credible commitment that attracts institutional clients.

Recommended approach: **Work Token (insurance staking) + fair launch distribution via broker points program.**

---

## Option A: Governance Token on Base

### Mechanics
Token holders vote on protocol parameters: fee rates, leverage limits, approved assets, treasury spending, insurance fund allocation.

### Pros
- Simple to implement (OpenZeppelin Governor)
- Familiar model — investors know what they're buying
- Stays on Base — no new chain complexity

### Cons
- **Governance in a B2B context is nearly worthless.** The "community" of Anduin is a small set of broker operators and liquidity providers. They don't need a token to coordinate — they need SLAs and contracts.
- Fee rates and leverage limits are business decisions, not governance decisions. If Anduin is run well, governance changes rarely. If it's run poorly, governance won't save it.
- Token price becomes completely disconnected from protocol performance. There's no mechanism that links "protocol does well → token price goes up" other than speculation.
- Pure governance tokens are considered securities by most regulatory frameworks in 2026. The SEC's 2024-2025 enforcement wave made this clear — if there's no utility other than voting, it's an unregistered security.
- **Verdict: Reject.** Governance should be a feature of whichever token structure is chosen, not the primary value prop.

---

## Option B: Work Token / Insurance Staking (Recommended)

### Mechanics
Token holders stake into the Anduin insurance fund. They earn a share of protocol fees (real yield — USDC from settlement, lending, and issuance revenue). In exchange, they are the last resort backstop: if the 5-layer waterfall is exhausted, stakers absorb losses up to their staked amount.

This is the "underwriter" model. Stakers are insurance underwriters. Brokers pay premiums (fees). When things go wrong, underwriters pay claims.

### Why this works economically
- **Clear demand driver:** To earn fees, you must stake. Token demand is directly tied to fee revenue.
- **Clear supply constraint:** Staking locks tokens. Circulating supply shrinks as protocol usage grows.
- **Credible commitment:** A protocol with $50M staked in its insurance fund is more attractive to institutional brokers than one without. The token creates a self-reinforcing flywheel: more stakers → larger insurance fund → larger broker commitments → more fees → more staker yield → more stakers.
- **Real yield:** Fees paid in USDC, not in token emissions. This is the standard in 2026. Inflationary yields are dead.

### Fee structure for stakers
- Settlement fees: ~2-5 bps on settled notional
- Lending interest spread: portion of interest margin
- Issuance fees: portion of issuance revenue
- Suggested staker share: 40-60% of protocol revenue (rest to treasury + team)

### Risk management for stakers
- Staking lockup: 7-14 day unbonding period (prevents bank runs during stress)
- Slash limits: maximum loss per event capped at X% of staked value
- Tiered seniority: early stakers get higher yield but also higher slash exposure

### veToken extension (2026 standard)
- Lock tokens for 1-4 years → receive veANDUIN
- veANDUIN boosts yield share (up to 2.5x) and governance weight
- Prevents mercenary capital — long-term stakers rewarded over yield farmers

### Cons
- Stakers bear real risk. Tail events (mass broker insolvency) could slash stakers badly.
- Requires sufficient TVL to be meaningful as insurance. A $1M staked fund backing $100M in settlements is not credible. Bootstrap problem.
- Complex to communicate to retail.

### Verdict: **Strongest option.** Pursue this.

---

## Option C: Anduin L2 with Sequencer Token

### Max's idea
"If a broker stays isolated, no token/chain other than Base. But as soon as netting is needed, abstract onto its own chain — client connects and has collateral on Base, Anduin nets on its own L2."

### The appeal
- Sequencer revenue is defensible and predictable
- Own L2 creates full control over execution environment
- Can build a richer ecosystem of apps on the Anduin chain
- Sequencer token = clear utility (pay for blockspace, stake to be a sequencer)

### Why this is probably wrong (at current scale)

**1. Engineering overhead is massive.**
Building and maintaining an L2 — even with OP Stack or Arbitrum Orbit — is an 18-24 month project. You need a sequencer infrastructure team, a DA layer, bridge contracts, monitoring. This is Coinbase-scale work. Anduin is pre-revenue. The opportunity cost is enormous.

**2. Cross-chain introduces correctness risk in settlement.**
Settlement infrastructure demands correctness above all else. Every cross-chain bridge is an attack surface. Moving settlement state across chains — Base ↔ Anduin L2 — means bridge security becomes existential risk. If the bridge is exploited, broker funds are at risk. Brokers will not accept this.

**3. It's not necessary for netting.**
Multi-broker netting can be done entirely on Base using batched settlement contracts. The gas cost is higher per-transaction but the correctness guarantee is higher. At current scale (pre-$1B daily volume), the economics don't justify a separate chain.

**4. Fragmented liquidity.**
If collateral lives on Base but netting lives on Anduin L2, you have two places to track exposure. Liquidation logic becomes cross-chain. This creates latency and coordination problems that kill the product UX.

**5. "Own L2" is no longer a differentiator in 2026.**
Every DeFi protocol with a roadmap has an L2 or L3 plan. It's table stakes narrative, not competitive moat. The sequencer token story is well-understood and already crowded (dYdX, Hyperliquid, etc.).

**6. The real threshold for your own chain: ~$10M+ daily transactions.**
Anduin should revisit the L2 question when it's processing $10M+ settlement transactions per day. At that volume, the economics justify dedicated blockspace and the engineering investment makes sense.

### The kernel of truth
Max is right that netting creates natural chain-level coordination. The right technical implementation is not a separate L2 today, but rather: **dedicated settlement batches** on Base with off-chain netting computation. Same economic result. Zero bridge risk.

### Verdict: **Reject for now.** Revisit at $10M+ daily transactions. Flag as Phase 3 roadmap item.

---

## Option D: Points → Fair Launch Token

### Mechanics
No VC round. No pre-mine. Broker operators earn "Anduin Points" based on:
- Volume settled through the protocol
- TVL contributed to lending pools
- Duration of continuous protocol usage

At Token Generation Event (TGE), points convert to tokens. The community gets the majority allocation.

### Why this works in 2026
Hyperliquid's HYPE launch (late 2024) proved this model definitively. 31% of supply to the community (60M HYPE) with no VC allocation. Result: immediate $2B+ FDV, community deeply aligned, zero dump pressure from VC lockup cliffs.

### Why it's hard for B2B infra
- "Points" programs are designed for consumer behavior. Brokers are institutional clients.
- Brokers care about their clients' experience, not token speculation. The incentive design needs to be different.
- Risk of gaming: brokers could fake volume to earn points.

### Adaptation for Anduin
- Points earned on verified settled notional (on-chain, unfakeable)
- Points earned on locked TVL in lending pools (time-weighted)
- No bonus for referrals or social activity — pure protocol usage
- Brokers must be KYB'd to participate → prevents sybil

### Verdict: **Use as distribution mechanism, not primary value capture.** Combine with Option B.

---

## Recommended Approach: Work Token + Fair Launch

### Structure
- **Token utility:** Insurance staking, fee capture, veToken governance
- **Distribution:** Points-based fair launch, no VC pre-mine (or minimal: <10% with 4-year vesting)
- **Yield:** Real yield in USDC from protocol fees
- **Lockup mechanics:** veANDUIN model for yield boost and governance

### Token distribution (suggested)
| Allocation | % | Vesting |
|---|---|---|
| Broker points airdrop | 40% | Earned over 24 months of usage |
| Community / ecosystem | 20% | 4-year release via staking rewards |
| Team | 15% | 4-year vest, 1-year cliff |
| Treasury | 15% | Protocol-controlled, deployed via governance |
| Early investors (optional) | 10% | 3-year vest, 6-month cliff — only if needed |

If you can avoid VC funding: cut investor allocation to 0% and redistribute to community. Use revenue to fund operations.

### Why no VC is better in 2026
- VC tokens dump at cliff. Community knows it. Token never escapes the overhang.
- Hyperliquid raised $0 from VCs and launched the most successful perp DEX token in history.
- B2B infra funded by VC = pressure to charge brokers more than the market will bear → lose clients → protocol dies.
- Alternative: revenue-based financing or protocol-owned treasury bonds.

---

## Modern Tokenomics Principles (2026)

### What works
1. **Real yield.** Fees paid in stablecoins, not in token. If you can only offer yield by printing more token, you don't have a business.
2. **Long lockups for insiders.** 4-year vesting, 1-year cliff minimum. Anything shorter signals short-termism.
3. **veToken mechanics.** Aligns long-term holders with protocol governance. Prevents mercenary capital.
4. **Protocol-owned liquidity (POL).** Buy and own your own DEX liquidity instead of paying LPs mercenary rates. Curve/Convex wars are over — POL is now the default.
5. **Fair launch or close to it.** Community-first distribution. Maximum 10-15% to insiders at launch.
6. **Transparent emissions schedule.** Fully published from day 1. No "we'll figure it out" — that's how you lose trust.
7. **Buyback and burn (optional but powerful).** Use protocol revenue to buy and burn tokens. Direct demand from the protocol itself. Works well with real yield.

### What doesn't work
1. **Inflationary staking rewards.** Yield that comes from minting new tokens is a Ponzi. APY drops as supply grows, holders sell, price drops, new entrants avoid. Spiral.
2. **VC-heavy allocations.** Cliff dumps destroy retail confidence permanently. The market has learned to check tokenomics before buying.
3. **Opaque vesting.** "Team tokens are locked" without on-chain verification = red flag.
4. **Governance theater.** Voting on parameters that the team can override. Community sees through it.
5. **Points gamification for B2B.** Leaderboards, referral codes, social quests are consumer mechanics. Institutional clients find them undignified.

### Lessons from specific launches
- **Hyperliquid HYPE:** No VCs, community-first, real yield from trading fees. FDV $8B+ at launch. Template for infrastructure tokens.
- **GMX:** Real yield (ETH/AVAX fees to GLP stakers), worked until it didn't (capital efficiency issues). Good example of real yield failing when the model is wrong.
- **Uniswap UNI:** Great governance token that captures no value. Classic failure mode. Still at 80% discount to 2021 peak despite dominant market position.
- **dYdX DYDX:** V3 token was pure governance. V4 migrated to Cosmos chain with staking and real yield. Correct diagnosis. Expensive lesson.

---

## Community Building for B2B Infrastructure

### The fundamental challenge
Anduin's end users are *brokers*, not retail. Retail doesn't run broker software. So standard "build a Discord, launch an NFT collection, run a meme contest" community playbook doesn't apply.

You're building a community of:
1. **Broker operators** — your customers. Want reliability, SLAs, developer docs.
2. **Liquidity providers / stakers** — your insurance underwriters. Want yield and transparency.
3. **Developers** — building on Anduin APIs. Want documentation, SDKs, and bounties.

### Phase 1: Operators (Months 1-12)
*Before token launch.*
- Private beta with 3-5 brokers. Give them equity, not tokens, at this stage — tokens too early.
- Bi-weekly operator calls. Build relationships, not audience.
- Technical documentation that actually works. This is the community.
- GitHub: open-source contracts. Audit reports public. Transparency builds trust.
- Operator forum: private Notion or Slack, not a public Discord.

### Phase 2: Stakers and LPs (Months 6-18)
*Around token launch.*
- Public launch of staking. First stakers get highest yield (bootstrap the insurance fund).
- Public Discord and forum for stakers. Clear risk disclosures. No hype.
- Monthly protocol metrics published: volume settled, fees earned, insurance fund size.
- On-chain transparency: all contracts verified, all fees traceable.
- Educational content: "What does it mean to stake in an insurance fund?" Most retail has no idea.

### Phase 3: Developer ecosystem (Months 12-24)
- SDK for brokers to integrate (Python, TypeScript)
- Grant program: fund teams building on Anduin APIs (risk dashboards, analytics, etc.)
- Hackathons focused on institutional DeFi tools
- API marketplace: brokers can subscribe to Anduin's data feeds

### What to avoid
- Meme culture. Anduin is infrastructure. The brand needs to signal trust, not entertainment.
- Hype without substance. If you tweet "big announcement soon" before you have revenue, you lose credibility with the institutional clients who matter.
- Token launch before product-market fit. The token should reward existing users, not recruit future ones.

---

## Open Questions and Risks

### Regulatory
- Is the staking/insurance token a security? Likely yes in most jurisdictions if stakers have "expectation of profit from others' efforts." Consult legal before launch.
- The points → fair launch mechanism may help with the Howey Test (distribution based on usage, not investment). But this is not settled law.
- US market: probably launch offshore first. EU: MiCA compliance needed in 2026.

### Bootstrap problem
- Insurance staking only becomes credible at $20M+ TVL. Getting there from zero requires either (a) protocol seeding the fund from treasury, (b) very high early yields to attract capital, or (c) launching without the staking mechanism and adding it later.
- Recommended: Protocol seeds $1-2M from treasury at launch. Offers 20% APY for first 6 months (from fee revenue + treasury subsidy). Use this to bootstrap staking TVL.

### Token/product timing
- Don't launch the token until you have at least 3 paying broker clients and $10M+ in monthly settled notional.
- A token on a protocol with no usage is a meme coin. Do the product work first.

### Network effect vs token timing
- The multi-broker netting network effect is the core moat. But it requires multiple brokers to be live.
- Token launch can accelerate broker adoption (token incentives for integration) but also creates pressure to rush integrations before they're ready.
- Recommendation: Launch token no earlier than broker #3, after $50M cumulative settled volume.

---

*Document prepared by Dribel, AI business partner. Critical feedback welcome — the goal is to find the right structure, not to validate an existing idea.*
