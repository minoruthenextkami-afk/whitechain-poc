# Whitechain Bridge — PoC and vulnerability reports

This repo contains executable Foundry tests for two Medium-severity findings in the Whitechain Bridge program on HackenProof.

## What's in here

| File | Purpose |
|------|---------|
| `test/MediumSeverityFindings.t.sol` | M3 replay test + M4 bytes32 truncation test |
| `test/WhitechainBridgeTestBase.sol` | Deployment harness with real ERC1967Proxy instances |
| `test/FalseReturnERC20.sol` | ERC-20 mock that returns false instead of reverting |
| `test/M1UncheckedTransferReturn.t.sol` | M1 unchecked transfer return test (separate finding) |

## M3 — receiveTokens has no replay protection

**Summary**

`receiveTokens` is the only way bridged funds get paid out, and there's no replay protection on the withdrawal side. The function accepts an `externalId` that's documented in `IBridge.sol` as "an external identifier for tracking the bridge transaction", emits it once in the `Withdrawal` event, and then forgets about it completely. `usedHashes`, which prevents replays on the deposit side in `bridgeTokens`, is never referenced in `receiveTokens`. The only real limit on how many times a withdrawal can be replayed is the `dailyLimits` check — a rolling 24-hour volume cap that resets every day. A relayer can call the same withdrawal over and over within that window and drain bridge liquidity up to the daily limit.

**Contracts**
- Bridge: `0x8F4D5bC9379beF9c209C895a1d6e7c26F64fE14F` (chain 1874)
- Mapper: `0x8f3FF368cd820910cB1A62acee5548BC354599Bf`
- Source: https://github.com/whitechain-labs/bridge-contracts
- Affected: `Bridge.sol` lines 251–317 (`receiveTokens`), 494–510 (`_checkAndUpdateDailyLimit`)

**Reproduction**
1. Multisig registers a withdrawal mapping (`withdrawType=Unlock`, `isCoin=false`)
2. Someone funds the bridge with the mapped token
3. Relayer calls `receiveTokens` with `externalId=X`, `mapId=1`, `amount=A`
4. Transaction goes through, `Withdrawal` event fires, daily volume tracker updates
5. Relayer calls `receiveTokens` again with the exact same `externalId=X`, same `mapId`, same `amount`
6. It succeeds again. Nothing blocks it.
7. Keep going until the daily limit is hit.

**PoC test**
```bash
forge test --match-test test_M5_receiveTokens_replayable_with_identical_externalId -vvv
```

**Expected result**: Test passes. Two consecutive `receiveTokens` calls with identical `externalId` both succeed and emit two `Withdrawal` events.

**Fix**
```solidity
mapping(bytes32 => bool) public usedExternalIds;

function receiveTokens(ReceiveTokensParams calldata receiveTokensParams)
    external
    nonReentrant
    onlyRole(RELAYER_ROLE)
    nonZeroBytes32(receiveTokensParams.fromAddress)
    nonZeroBytes32(receiveTokensParams.toAddress)
    nonZeroUint256(receiveTokensParams.amount)
{
    require(!usedExternalIds[receiveTokensParams.externalId], "Bridge: externalId already used");
    usedExternalIds[receiveTokensParams.externalId] = true;
    // ... rest of function unchanged
}
```

## M4 — bytes32 destination truncation burns funds

**Summary**

The bridge is designed to carry identifiers wider than an EVM address — `bytes32` token and address fields exist precisely to support non-EVM networks such as Tron. On the withdrawal path that width is discarded with a bare `uint160` cast, while the only validation, the `nonZeroBytes32` modifier, is applied to the full 32 bytes. A destination value that is non-zero as `bytes32` but zero in its low 20 bytes therefore passes every check, resolves to `address(0)`, and the payout completes successfully with the funds destroyed instead of delivered.

**Contracts**
- Bridge: `0x8F4D5bC9379beF9c209C895a1d6e7c26F64fE14F` (chain 1874)
- Mapper: `0x8f3FF368cd820910cB1A62acee5548BC354599Bf`
- Source: https://github.com/whitechain-labs/bridge-contracts
- Affected: `Bridge.sol` line 281 (`address(uint160(uint256(toAddress)))` in `receiveTokens`)

**Reproduction**
1. Multisig registers a coin withdrawal mapping (`isCoin=true`, `withdrawType=Unlock`)
2. The bridge holds native liquidity
3. Relayer calls `receiveTokens` with `toAddress = bytes32(uint256(1) << 160)`
   This is `0x0000000000000000000000000000000001` followed by 20 zero bytes
4. `nonZeroBytes32` modifier passes because the full 32 bytes are non-zero
5. `uint160(uint256(toAddress))` yields `address(0)` because the low 160 bits are all zero
6. `address(0).call{value: A}("")` succeeds, `require(success)` passes
7. `Withdrawal` event is emitted, transaction completes
8. A units are now held by `address(0)` and are unrecoverable

**PoC test**
```bash
forge test --match-test test_M6_nonzero_bytes32_truncates_to_zero_address -vvvv
```

**Expected result**: Test passes. The test constructs a `bytes32` destination where only the high 96 bits are non-zero, calls `receiveTokens` with that value, and shows the call succeeds while the recipient resolves to `address(0)`. The assertion proves the ETH is sent to `address(0)` and the bridge balance decreases accordingly.

**Fix**
```solidity
address recipient = address(uint160(uint256(receiveTokensParams.toAddress)));
require(recipient != address(0), "Bridge: Invalid recipient address");

// Apply at all three payout sites:
// line 281: coin Unlock
// line 294: token Mint
// line 301: token Unlock
```

## Severity

Both findings are Medium on the program's scale. M4 has a stronger Integrity argument (permanent fund destruction, no recovery path), but both fall within the program's Medium band ($300–$500). The program pays only the highest-severity finding per reporter.

## Setup

```bash
git clone https://github.com/minoruthenextkami-afk/whitechain-poc.git
cd whitechain-poc
forge build
```

Run all tests:
```bash
forge test -vvvv
```

All 6 tests pass.

## Contact

[Your HackenProof username]
