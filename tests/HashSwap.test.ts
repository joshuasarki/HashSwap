
import { describe, expect, it } from "vitest";
import {
  boolCV,
  bufferCV,
  ClarityType,
  noneCV,
  principalCV,
  someCV,
  uintCV,
} from "@stacks/transactions";
import type { ClarityValue, SomeCV, TupleCV } from "@stacks/transactions";
import { sha256 } from "@noble/hashes/sha256";

const CONTRACT = "HashSwap";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

const ERR_ALREADY_EXISTS = 100n;
const ERR_INVALID_PREIMAGE = 101n;
const ERR_TOO_EARLY = 102n;
const ERR_NOT_SENDER = 103n;
const ERR_NOT_RECIPIENT = 104n;
const ERR_CONTRACT_PAUSED = 106n;
const ERR_UNAUTHORIZED = 108n;
const ERR_CLAIM_TOO_SMALL = 113n;
const ERR_MAX_CLAIMS_REACHED = 114n;
const ERR_EMERGENCY_NOT_ENABLED = 115n;
const ERR_EMERGENCY_TOO_EARLY = 116n;

const makeSeededBytes = (seed: number) => new Uint8Array(32).fill(seed);

const makeHashPair = (seed: number) => {
  const preimage = makeSeededBytes(seed);
  const hash = sha256(preimage);
  return { preimage, hash };
};

const isSome = (cv: ClarityValue): cv is SomeCV => cv.type === ClarityType.OptionalSome;

const isTuple = (cv: ClarityValue): cv is TupleCV => cv.type === ClarityType.Tuple;

const getSwap = (hash: Uint8Array) => {
  const entry = simnet.getMapEntry(CONTRACT, "swaps", bufferCV(hash));
  if (!isSome(entry)) {
    throw new Error("expected swap to exist");
  }
  if (!isTuple(entry.value)) {
    throw new Error("expected swap tuple");
  }
  return entry.value;
};

const getContractBalance = (caller: string) =>
  simnet.callReadOnlyFn(CONTRACT, "get-contract-balance", [], caller).result;

describe("HashSwap core flows", () => {
  it("locks and claims a basic swap", () => {
    const { preimage, hash } = makeHashPair(1);
    const amount = 1_000n;
    const timeout = simnet.blockHeight + 10;

    const lock = simnet.callPublicFn(
      CONTRACT,
      "lock-funds",
      [
        bufferCV(hash),
        uintCV(timeout),
        someCV(principalCV(wallet2)),
        noneCV(),
        uintCV(amount),
      ],
      wallet1,
    );
    expect(lock.result).toBeOk(boolCV(true));

    const duplicate = simnet.callPublicFn(
      CONTRACT,
      "lock-funds",
      [
        bufferCV(hash),
        uintCV(timeout + 1),
        someCV(principalCV(wallet2)),
        noneCV(),
        uintCV(amount),
      ],
      wallet1,
    );
    expect(duplicate.result).toBeErr(uintCV(ERR_ALREADY_EXISTS));

    const badPreimage = makeSeededBytes(9);
    const badClaim = simnet.callPublicFn(
      CONTRACT,
      "claim",
      [bufferCV(badPreimage)],
      wallet2,
    );
    expect(badClaim.result).toBeErr(uintCV(ERR_INVALID_PREIMAGE));

    const wrongRecipient = simnet.callPublicFn(
      CONTRACT,
      "claim",
      [bufferCV(preimage)],
      wallet3,
    );
    expect(wrongRecipient.result).toBeErr(uintCV(ERR_NOT_RECIPIENT));

    const balanceAfterLock = getContractBalance(wallet1);
    expect(balanceAfterLock).toBeOk(uintCV(amount));

    const swap = getSwap(hash);
    expect(swap.value["status"]).toBeAscii("open");
    expect(swap.value["remaining-amount"]).toBeUint(amount);
    expect(swap.value["claim-count"]).toBeUint(0);
    expect(swap.value["recipient"]).toBeSome(principalCV(wallet2));
    expect(swap.value["memo"]).toBeNone();

    const claim = simnet.callPublicFn(
      CONTRACT,
      "claim",
      [bufferCV(preimage)],
      wallet2,
    );
    expect(claim.result).toBeOk(boolCV(true));

    const swapAfter = getSwap(hash);
    expect(swapAfter.value["status"]).toBeAscii("claimed");
    expect(swapAfter.value["remaining-amount"]).toBeUint(0);
    expect(swapAfter.value["claim-count"]).toBeUint(1);

    const balanceAfterClaim = getContractBalance(wallet1);
    expect(balanceAfterClaim).toBeOk(uintCV(0));
  });

  it("supports partial claims and enforces limits", () => {
    const { preimage, hash } = makeHashPair(2);
    const amount = 1_000n;
    const minClaim = 100n;
    const maxClaims = 2n;
    const timeout = simnet.blockHeight + 10;

    const lock = simnet.callPublicFn(
      CONTRACT,
      "lock-funds-advanced",
      [
        bufferCV(hash),
        uintCV(timeout),
        someCV(principalCV(wallet2)),
        noneCV(),
        uintCV(amount),
        uintCV(minClaim),
        uintCV(maxClaims),
      ],
      wallet1,
    );
    expect(lock.result).toBeOk(boolCV(true));

    const tooSmall = simnet.callPublicFn(
      CONTRACT,
      "partial-claim",
      [bufferCV(preimage), uintCV(50)],
      wallet2,
    );
    expect(tooSmall.result).toBeErr(uintCV(ERR_CLAIM_TOO_SMALL));

    const claim1 = simnet.callPublicFn(
      CONTRACT,
      "partial-claim",
      [bufferCV(preimage), uintCV(150)],
      wallet2,
    );
    expect(claim1.result).toBeOk(boolCV(true));

    let swap = getSwap(hash);
    expect(swap.value["status"]).toBeAscii("open");
    expect(swap.value["remaining-amount"]).toBeUint(850);
    expect(swap.value["claim-count"]).toBeUint(1);

    const claim2 = simnet.callPublicFn(
      CONTRACT,
      "partial-claim",
      [bufferCV(preimage), uintCV(150)],
      wallet2,
    );
    expect(claim2.result).toBeOk(boolCV(true));

    swap = getSwap(hash);
    expect(swap.value["remaining-amount"]).toBeUint(700);
    expect(swap.value["claim-count"]).toBeUint(2);

    const maxed = simnet.callPublicFn(
      CONTRACT,
      "partial-claim",
      [bufferCV(preimage), uintCV(150)],
      wallet2,
    );
    expect(maxed.result).toBeErr(uintCV(ERR_MAX_CLAIMS_REACHED));
  });

  it("refunds after timeout and only for sender", () => {
    const { hash } = makeHashPair(3);
    const amount = 500n;
    const timeout = simnet.blockHeight + 10;

    const lock = simnet.callPublicFn(
      CONTRACT,
      "lock-funds",
      [bufferCV(hash), uintCV(timeout), noneCV(), noneCV(), uintCV(amount)],
      wallet1,
    );
    expect(lock.result).toBeOk(boolCV(true));

    const tooEarly = simnet.callPublicFn(CONTRACT, "refund", [bufferCV(hash)], wallet1);
    expect(tooEarly.result).toBeErr(uintCV(ERR_TOO_EARLY));

    simnet.mineEmptyBlocks(12);

    const notSender = simnet.callPublicFn(CONTRACT, "refund", [bufferCV(hash)], wallet2);
    expect(notSender.result).toBeErr(uintCV(ERR_NOT_SENDER));

    const refund = simnet.callPublicFn(CONTRACT, "refund", [bufferCV(hash)], wallet1);
    expect(refund.result).toBeOk(boolCV(true));

    const swap = getSwap(hash);
    expect(swap.value["status"]).toBeAscii("refunded");
    expect(swap.value["remaining-amount"]).toBeUint(0);
  });

  it("respects admin gating and pause controls", () => {
    const unauthorizedPause = simnet.callPublicFn(CONTRACT, "pause", [], wallet1);
    expect(unauthorizedPause.result).toBeErr(uintCV(ERR_UNAUTHORIZED));

    const pause = simnet.callPublicFn(CONTRACT, "pause", [], deployer);
    expect(pause.result).toBeOk(boolCV(true));

    const { hash } = makeHashPair(4);
    const timeout = simnet.blockHeight + 10;
    const lockWhilePaused = simnet.callPublicFn(
      CONTRACT,
      "lock-funds",
      [bufferCV(hash), uintCV(timeout), noneCV(), noneCV(), uintCV(100)],
      wallet1,
    );
    expect(lockWhilePaused.result).toBeErr(uintCV(ERR_CONTRACT_PAUSED));

    const unpause = simnet.callPublicFn(CONTRACT, "unpause", [], deployer);
    expect(unpause.result).toBeOk(boolCV(true));

    const lock = simnet.callPublicFn(
      CONTRACT,
      "lock-funds",
      [bufferCV(hash), uintCV(timeout + 1), noneCV(), noneCV(), uintCV(100)],
      wallet1,
    );
    expect(lock.result).toBeOk(boolCV(true));
  });

  it("allows emergency recovery when enabled and timeout passed", () => {
    const { hash } = makeHashPair(5);
    const amount = 400n;
    const timeout = simnet.blockHeight + 10;

    const lock = simnet.callPublicFn(
      CONTRACT,
      "lock-funds",
      [bufferCV(hash), uintCV(timeout), noneCV(), noneCV(), uintCV(amount)],
      wallet1,
    );
    expect(lock.result).toBeOk(boolCV(true));

    const notEnabled = simnet.callPublicFn(
      CONTRACT,
      "emergency-recover",
      [bufferCV(hash)],
      wallet1,
    );
    expect(notEnabled.result).toBeErr(uintCV(ERR_EMERGENCY_NOT_ENABLED));

    const setTimeout = simnet.callPublicFn(
      CONTRACT,
      "set-emergency-timeout",
      [uintCV(1001)],
      deployer,
    );
    expect(setTimeout.result).toBeOk(boolCV(true));

    const enable = simnet.callPublicFn(
      CONTRACT,
      "toggle-recovery",
      [boolCV(true)],
      deployer,
    );
    expect(enable.result).toBeOk(boolCV(true));

    const tooEarly = simnet.callPublicFn(
      CONTRACT,
      "emergency-recover",
      [bufferCV(hash)],
      wallet1,
    );
    expect(tooEarly.result).toBeErr(uintCV(ERR_EMERGENCY_TOO_EARLY));

    simnet.mineEmptyBlocks(1002);

    const recover = simnet.callPublicFn(
      CONTRACT,
      "emergency-recover",
      [bufferCV(hash)],
      wallet1,
    );
    expect(recover.result).toBeOk(boolCV(true));

    const swap = getSwap(hash);
    expect(swap.value["status"]).toBeAscii("recovered");
    expect(swap.value["remaining-amount"]).toBeUint(0);
  });
});
