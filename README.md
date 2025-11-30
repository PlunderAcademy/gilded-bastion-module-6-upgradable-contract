# Gilded Bastion - Module 6: Upgradable Contract

This is a completed module from [Plunder Academy](https://plunderacademy.com/lessons/island4/upgradable-contract-practical).

## Setup

To set up and use this project correctly, please follow the **Deploying with Foundry** section in the module lesson.

## Usage

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Deploy

```shell
forge script script/Deploy.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```

### Upgrade

```shell
forge script script/Upgrade.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```
