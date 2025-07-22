# HashSwap Smart Contract

This project implements a Hash Time-Locked Swap (HTLS) contract for STX tokens on the Stacks blockchain using Clarity. It enables atomic swaps of STX with hashlocks and timelocks, providing secure, trustless exchange between parties.

## Features

- **Atomic Swaps:** Lock STX tokens with a hashlock and timelock.
- **Claim:** Recipient can claim locked STX by revealing the correct preimage.
- **Refund:** Sender can refund their STX after the timeout expires.
- **Admin Controls:** Pause/unpause contract and manage recipient whitelist.
- **Swap Status:** Track swap status (`open`, `claimed`, `refunded`).
- **Events:** Emits swap events using `print` statements.

## Contract Functions

### Public Functions

- `lock-funds(hash-secret, timeout-block, recipient, memo, amount)`
  - Locks STX in the contract for a swap.
- `claim(preimage)`
  - Claims locked STX by providing the correct preimage.
- `refund(hash-secret)`
  - Refunds STX to sender after timeout.
- `pause()`
  - Pauses contract operations (admin only).
- `unpause()`
  - Resumes contract operations (admin only).
- `add-recipient(addr)`
  - Adds a recipient to the whitelist (admin only).

### Read-Only Functions

- `get-swap(hash-secret)`
  - Returns swap details for a given hash.
- `is-paused()`
  - Returns contract pause status.
- `get-admin()`
  - Returns admin address.
- `is-whitelisted(addr)`
  - Checks if an address is whitelisted.

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

## Usage

1. **Lock Funds:**  
   Sender calls `lock-funds` with a hash of the secret, timeout, recipient, memo, and amount.
2. **Claim Swap:**  
   Recipient calls `claim` with the preimage before timeout to receive STX.
3. **Refund Swap:**  
   Sender calls `refund` after timeout to reclaim STX if unclaimed.

## Admin Operations

- Use `pause` and `unpause` to control contract activity.
- Use `add-recipient` to manage whitelisted addresses.

## Events

Events are emitted via `print` statements for swap creation, claim, refund, pause, and unpause.

## License

MIT License

---

**Note:**  
This contract is written in Clarity for the Stacks blockchain. Test thoroughly before deploying to mainnet.
