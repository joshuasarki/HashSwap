# HashSwap Smart Contract

This project implements a Hash Time-Locked Swap (HTLS) contract for STX tokens on the Stacks blockchain using Clarity. It enables atomic swaps of STX with hashlocks and timelocks, providing secure, trustless exchange between parties.

## Features

- **Atomic Swaps:** Lock STX tokens with a hashlock and timelock.
- **Partial Claims:** Swaps can be claimed in multiple parts, with configurable minimum claim amounts and maximum claims.
- **Claim History:** Every claim (full or partial) is recorded for transparency.
- **Emergency Recovery:** Admin or sender can recover funds from long-stuck swaps if emergency recovery is enabled.
- **Claim:** Recipient can claim locked STX by revealing the correct preimage.
- **Refund:** Sender can refund their STX after the timeout expires.
- **Admin Controls:** Pause/unpause contract, manage recipient whitelist, and configure emergency recovery.
- **Swap Status:** Track swap status (`open`, `claimed`, `refunded`, `recovered`).
- **Events:** Emits swap events using `print` statements.

## Contract Functions

### Public Functions

- `lock-funds(hash-secret, timeout-block, recipient, memo, amount)`
  - Locks STX in the contract for a basic swap.
- `lock-funds-advanced(hash-secret, timeout-block, recipient, memo, amount, min-claim-amount, max-claims)`
  - Locks STX in the contract with support for partial claims.
- `claim(preimage)`
  - Claims the full remaining amount by providing the correct preimage.
- `partial-claim(preimage, claim-amount)`
  - Claims a specified amount (if allowed) by providing the correct preimage.
- `refund(hash-secret)`
  - Refunds STX to sender after timeout.
- `emergency-recover(hash-secret)`
  - Recovers funds from very old swaps if emergency recovery is enabled.
- `pause()`
  - Pauses contract operations (admin only).
- `unpause()`
  - Resumes contract operations (admin only).
- `add-recipient(addr)`
  - Adds a recipient to the whitelist (admin only).
- `toggle-recovery(enabled)`
  - Enables or disables emergency recovery (admin only).
- `set-emergency-timeout(blocks)`
  - Sets the emergency timeout duration (admin only).

### Read-Only Functions

- `get-swap(hash-secret)`
  - Returns swap details for a given hash.
- `get-claim-history(hash-secret, claim-id)`
  - Returns details of a specific claim for a swap.
- `get-swap-stats(hash-secret)`
  - Returns progress, claims used/remaining, and age of a swap.
- `get-contract-balance()`
  - Returns the contract's STX balance.
- `is-paused()`
  - Returns contract pause status.
- `get-admin()`
  - Returns admin address.
- `is-whitelisted(addr)`
  - Checks if an address is whitelisted.
- `get-emergency-settings()`
  - Returns emergency recovery settings.

## Error Codes

- `ERR_ALREADY_EXISTS` (u100): Swap already exists.
- `ERR_INVALID_PREIMAGE` (u101): Invalid preimage.
- `ERR_TOO_EARLY` (u102): Timeout not reached.
- `ERR_NOT_SENDER` (u103): Caller is not the sender.
- `ERR_NOT_RECIPIENT` (u104): Caller is not the recipient.
- `ERR_SWAP_NOT_FOUND` (u105): Swap not found.
- `ERR_CONTRACT_PAUSED` (u106): Contract is paused.
- `ERR_INVALID_TIMEOUT` (u107): Invalid timeout value.
- `ERR_UNAUTHORIZED` (u108): Unauthorized action.
- `ERR_INVALID_ADDRESS` (u109): Invalid address.
- `ERR_INVALID_AMOUNT` (u110): Invalid amount.
- `ERR_SWAP_NOT_OPEN` (u111): Swap is not open.
- `ERR_INSUFFICIENT_FUNDS` (u112): Not enough funds to claim.
- `ERR_CLAIM_TOO_SMALL` (u113): Claim amount is too small.
- `ERR_MAX_CLAIMS_REACHED` (u114): Maximum number of claims reached.
- `ERR_EMERGENCY_NOT_ENABLED` (u115): Emergency recovery not enabled.
- `ERR_EMERGENCY_TOO_EARLY` (u116): Emergency recovery too early.

## Usage

1. **Lock Funds:**  
   Sender calls `lock-funds` or `lock-funds-advanced` with a hash of the secret, timeout, recipient, memo, amount, and (optionally) partial claim settings.
2. **Claim Swap:**  
   Recipient calls `claim` or `partial-claim` with the preimage before timeout to receive STX.
3. **Refund Swap:**  
   Sender calls `refund` after timeout to reclaim STX if unclaimed.
4. **Emergency Recovery:**  
   Admin or sender can call `emergency-recover` for swaps stuck past the emergency timeout (if enabled).

## Admin Operations

- Use `pause` and `unpause` to control contract activity.
- Use `add-recipient` to manage whitelisted addresses.
- Use `toggle-recovery` and `set-emergency-timeout` to manage emergency recovery settings.

## Events

Events are emitted via `print` statements for swap creation, claim, partial claim, refund, emergency recovery, pause, unpause, and admin actions.

## License

MIT License

---

**Note:**  
This contract is written in Clarity for the Stacks blockchain. Test thoroughly before deploying to mainnet.
