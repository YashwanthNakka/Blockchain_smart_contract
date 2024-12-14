// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract BidirectionalPaymentChannel {
    address payable public partyA;
    address payable public partyB;
    uint256 public expirationTime; // Optional expiration time for force closure
    uint256 public challengeEndTime; // End time for the challenge period
    bool public underChallenge; // Indicates if the channel is under dispute
    bool public channelOpen; // Indicates if the channel is active

    struct ChannelState {
        uint256 balanceA; // Party A's balance
        uint256 balanceB; // Party B's balance
    }

    ChannelState public latestState;

    constructor(address payable _partyB, uint256 _expirationTime) payable {
        require(msg.value > 0, "Must deposit some amount to open the channel");

        partyA = payable(msg.sender);
        partyB = _partyB;
        expirationTime = _expirationTime;
        channelOpen = true;

        latestState = ChannelState({
            balanceA: msg.value,
            balanceB: 0 // Party B starts with no funds
        });
    }

    // Party B deposits funds into the channel
    function depositByPartyB() external payable {
        require(channelOpen, "Channel is closed");
        require(msg.sender == partyB, "Only Party B can deposit funds");
        require(msg.value > 0, "Must deposit a positive amount");

        latestState.balanceB += msg.value;
    }

    // Helper functions for signature validation
    function isValidSignature(
        bytes32 hash,
        bytes memory signature,
        address signer
    ) internal pure returns (bool) {
        bytes32 messageHash = prefixed(hash);
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);
        return ecrecover(messageHash, v, r, s) == signer;
    }

    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function splitSignature(bytes memory sig)
        internal
        pure
        returns (bytes32 r, bytes32 s, uint8 v)
    {
        require(sig.length == 65, "Invalid signature length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    // Initiate channel closure with a proposed state
    function initiateClose(
        uint256 balanceA,
        uint256 balanceB,
        bytes memory sigA,
        bytes memory sigB
    ) external {
        require(channelOpen, "Channel is already closed");
        require(
            isValidSignature(keccak256(abi.encode(balanceA, balanceB)), sigA, partyA),
            "Invalid signature from Party A"
        );
        require(
            isValidSignature(keccak256(abi.encode(balanceA, balanceB)), sigB, partyB),
            "Invalid signature from Party B"
        );

        require(balanceA + balanceB == latestState.balanceA + latestState.balanceB, "Invalid balance distribution");

        // Set the latest state and start the challenge period
        latestState = ChannelState(balanceA, balanceB);
        challengeEndTime = block.timestamp + 1 days; // Set a 1-day challenge period
        underChallenge = true;
    }

    // Submit a newer state during the challenge period
    function submitNewState(
        uint256 balanceA,
        uint256 balanceB,
        bytes memory sigA,
        bytes memory sigB
    ) external {
        require(underChallenge, "No active dispute");
        require(block.timestamp <= challengeEndTime, "Challenge period ended");
        require(
            isValidSignature(keccak256(abi.encode(balanceA, balanceB)), sigA, partyA),
            "Invalid signature from Party A"
        );
        require(
            isValidSignature(keccak256(abi.encode(balanceA, balanceB)), sigB, partyB),
            "Invalid signature from Party B"
        );

        require(balanceA + balanceB == latestState.balanceA + latestState.balanceB, "Invalid balance distribution");

        // Update the latest state to the new one
        latestState = ChannelState(balanceA, balanceB);
    }

    // Finalize the channel closure after the challenge period
    function finalizeClose() external {
        require(underChallenge, "No active dispute");
        require(block.timestamp > challengeEndTime, "Challenge period not ended");

        channelOpen = false;
        underChallenge = false;

        // Distribute funds based on the latest valid state
        if (latestState.balanceA > 0) partyA.transfer(latestState.balanceA);
        if (latestState.balanceB > 0) partyB.transfer(latestState.balanceB);
    }

    // Force close the channel if it has expired
    function forceCloseChannel() external {
        require(channelOpen, "Channel is already closed");
        require(block.timestamp >= expirationTime, "Channel has not expired yet");

        channelOpen = false;

        // Refund balances as per the latest state
        if (latestState.balanceA > 0) partyA.transfer(latestState.balanceA);
        if (latestState.balanceB > 0) partyB.transfer(latestState.balanceB);
    }
}
