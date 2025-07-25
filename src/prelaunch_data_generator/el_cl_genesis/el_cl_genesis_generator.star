shared_utils = import_module("../../shared_utils/shared_utils.star")

el_cl_genesis_data = import_module("./el_cl_genesis_data.star")

constants = import_module("../../package_io/constants.star")

GENESIS_VALUES_PATH = "/opt"
GENESIS_VALUES_FILENAME = "values.env"
GENESIS_CONTRACTS_FILENAME = "additional-contracts.json"
SHADOWFORK_FILEPATH = "/shadowfork"


def generate_el_cl_genesis_data(
    plan,
    image,
    genesis_generation_config_yml_template,
    genesis_additional_contracts_yml_template,
    genesis_unix_timestamp,
    network_params,
    total_num_validator_keys_to_preregister,
    latest_block,
):
    files = {}
    shadowfork_file = ""
    if latest_block != "":
        files[SHADOWFORK_FILEPATH] = latest_block
        shadowfork_file = SHADOWFORK_FILEPATH + "/latest_block.json"

    template_data = new_env_file_for_el_cl_genesis_data(
        genesis_unix_timestamp,
        total_num_validator_keys_to_preregister,
        shadowfork_file,
        network_params,
    )
    genesis_generation_template = shared_utils.new_template_and_data(
        genesis_generation_config_yml_template, template_data
    )

    additional_contracts_template_data = (
        new_additionsl_contracts_file_for_el_cl_genesis_data(
            network_params,
        )
    )
    additional_contracts_template = shared_utils.new_template_and_data(
        genesis_additional_contracts_yml_template, additional_contracts_template_data
    )

    genesis_values_and_dest_filepath = {}

    genesis_values_and_dest_filepath[
        GENESIS_VALUES_FILENAME
    ] = genesis_generation_template

    genesis_values_and_dest_filepath[
        GENESIS_CONTRACTS_FILENAME
    ] = additional_contracts_template

    genesis_generation_config_artifact_name = plan.render_templates(
        genesis_values_and_dest_filepath, "genesis-el-cl-env-file"
    )

    files[GENESIS_VALUES_PATH] = genesis_generation_config_artifact_name

    genesis = plan.run_sh(
        name="run-generate-genesis",
        description="Creating genesis",
        run="cp /opt/values.env /config/values.env && ./entrypoint.sh all && mkdir /network-configs && mv /data/metadata/* /network-configs/ && mv /data/parsed /network-configs/parsed",
        image=image,
        files=files,
        store=[
            StoreSpec(src="/network-configs/", name="el_cl_genesis_data"),
            StoreSpec(
                src="/network-configs/genesis_validators_root.txt",
                name="genesis_validators_root",
            ),
        ],
        wait=None,
    )

    genesis_validators_root = plan.run_sh(
        name="read-genesis-validators-root",
        description="Reading genesis validators root",
        run="cat /data/genesis_validators_root.txt",
        files={"/data": genesis.files_artifacts[1]},
        wait=None,
    )
    osaka_time = plan.run_sh(
        name="read-osaka-time",
        description="Reading osaka time from genesis",
        run="jq '.config.osakaTime' /data/genesis.json | tr -d '\n'",
        files={"/data": genesis.files_artifacts[0]},
    )

    osaka_enabled_check = plan.run_sh(
        name="check-osaka-enabled",
        description="Check if osaka time is enabled (not false)",
        run="test \"$(jq '.config.osakaTime // false' /data/genesis.json | tr -d '\n')\" != \"false\" && echo true || echo false",
        files={"/data": genesis.files_artifacts[0]},
    )

    result = el_cl_genesis_data.new_el_cl_genesis_data(
        genesis.files_artifacts[0],
        genesis_validators_root.output,
        osaka_time.output,
        osaka_enabled_check.output == "true",
    )

    return result


def new_env_file_for_el_cl_genesis_data(
    genesis_unix_timestamp,
    total_num_validator_keys_to_preregister,
    shadowfork_file,
    network_params,
):
    return {
        "UnixTimestamp": genesis_unix_timestamp,
        "NetworkId": constants.NETWORK_ID[network_params.network.split("-")[0]]
        if shadowfork_file
        else network_params.network_id,  # This will override the network_id if shadowfork_file is present. If you want to use the network_id, please ensure that you don't use "shadowfork" in the network name.
        "DepositContractAddress": network_params.deposit_contract_address,
        "SecondsPerSlot": network_params.seconds_per_slot,
        "PreregisteredValidatorKeysMnemonic": network_params.preregistered_validator_keys_mnemonic,
        "NumValidatorKeysToPreregister": total_num_validator_keys_to_preregister,
        "GenesisDelay": 0,  # This delay is already precaculated in the final_genesis_timestamp
        "GenesisGasLimit": network_params.genesis_gaslimit,
        "MaxPerEpochActivationChurnLimit": network_params.max_per_epoch_activation_churn_limit,
        "ChurnLimitQuotient": network_params.churn_limit_quotient,
        "EjectionBalance": network_params.ejection_balance,
        "Eth1FollowDistance": network_params.eth1_follow_distance,
        "AltairForkEpoch": "{0}".format(network_params.altair_fork_epoch),
        "BellatrixForkEpoch": "{0}".format(network_params.bellatrix_fork_epoch),
        "CapellaForkEpoch": "{0}".format(network_params.capella_fork_epoch),
        "DenebForkEpoch": "{0}".format(network_params.deneb_fork_epoch),
        "ElectraForkEpoch": "{0}".format(network_params.electra_fork_epoch),
        "FuluForkEpoch": "{0}".format(network_params.fulu_fork_epoch),
        "Eip7732ForkEpoch": "{0}".format(network_params.eip7732_fork_epoch),
        "Eip7805ForkEpoch": "{0}".format(network_params.eip7805_fork_epoch),
        "GenesisForkVersion": constants.GENESIS_FORK_VERSION,
        "AltairForkVersion": constants.ALTAIR_FORK_VERSION,
        "BellatrixForkVersion": constants.BELLATRIX_FORK_VERSION,
        "CapellaForkVersion": constants.CAPELLA_FORK_VERSION,
        "DenebForkVersion": constants.DENEB_FORK_VERSION,
        "ElectraForkVersion": constants.ELECTRA_FORK_VERSION,
        "FuluForkVersion": constants.FULU_FORK_VERSION,
        "Eip7732ForkVersion": constants.EIP7732_FORK_VERSION,
        "Eip7805ForkVersion": constants.EIP7805_FORK_VERSION,
        "ShadowForkFile": shadowfork_file,
        "MinValidatorWithdrawabilityDelay": network_params.min_validator_withdrawability_delay,
        "ShardCommitteePeriod": network_params.shard_committee_period,
        "DataColumnSidecarSubnetCount": network_params.data_column_sidecar_subnet_count,
        "SamplesPerSlot": network_params.samples_per_slot,
        "CustodyRequirement": network_params.custody_requirement,
        "MaxBlobsPerBlockElectra": network_params.max_blobs_per_block_electra,
        "TargetBlobsPerBlockElectra": network_params.target_blobs_per_block_electra,
        "BaseFeeUpdateFractionElectra": network_params.base_fee_update_fraction_electra,
        "Preset": network_params.preset,
        "AdditionalPreloadedContractsFile": GENESIS_VALUES_PATH
        + "/"
        + GENESIS_CONTRACTS_FILENAME,
        "PrefundedAccounts": json.encode(network_params.prefunded_accounts),
        "MaxPayloadSize": network_params.max_payload_size,
        "Bpo1Epoch": "{0}".format(network_params.bpo_1_epoch),
        "Bpo1MaxBlobs": network_params.bpo_1_max_blobs,
        "Bpo1TargetBlobs": network_params.bpo_1_target_blobs,
        "Bpo1BaseFeeUpdateFraction": network_params.bpo_1_base_fee_update_fraction,
        "Bpo2Epoch": "{0}".format(network_params.bpo_2_epoch),
        "Bpo2MaxBlobs": network_params.bpo_2_max_blobs,
        "Bpo2TargetBlobs": network_params.bpo_2_target_blobs,
        "Bpo2BaseFeeUpdateFraction": network_params.bpo_2_base_fee_update_fraction,
        "Bpo3Epoch": "{0}".format(network_params.bpo_3_epoch),
        "Bpo3MaxBlobs": network_params.bpo_3_max_blobs,
        "Bpo3TargetBlobs": network_params.bpo_3_target_blobs,
        "Bpo3BaseFeeUpdateFraction": network_params.bpo_3_base_fee_update_fraction,
        "Bpo4Epoch": "{0}".format(network_params.bpo_4_epoch),
        "Bpo4MaxBlobs": network_params.bpo_4_max_blobs,
        "Bpo4TargetBlobs": network_params.bpo_4_target_blobs,
        "Bpo4BaseFeeUpdateFraction": network_params.bpo_4_base_fee_update_fraction,
        "Bpo5Epoch": "{0}".format(network_params.bpo_5_epoch),
        "Bpo5MaxBlobs": network_params.bpo_5_max_blobs,
        "Bpo5TargetBlobs": network_params.bpo_5_target_blobs,
        "Bpo5BaseFeeUpdateFraction": network_params.bpo_5_base_fee_update_fraction,
        "WithdrawalType": "{0}".format(network_params.withdrawal_type),
        "WithdrawalAddress": network_params.withdrawal_address,
        "ValidatorBalance": int(network_params.validator_balance * 1000000000),
        "MinEpochsForDataColumnSidecarsRequests": network_params.min_epochs_for_data_column_sidecars_requests,
    }


def new_additionsl_contracts_file_for_el_cl_genesis_data(
    network_params,
):
    additional_contracts_json = network_params.additional_preloaded_contracts
    if type(additional_contracts_json) != "string":
        additional_contracts_json = json.encode(additional_contracts_json)

    return {
        "AdditionalPreloadedContracts": additional_contracts_json,
    }
