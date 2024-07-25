import { useContext, useEffect, useState, useRef } from "react";
import { formatUnits, parseUnits } from "@ethersproject/units";

import { Modal } from "./Modal";
import { Icon } from "./Icon";

import { useDebounce } from "../utils/use-debounce";
import { numberWithCommas } from "../utils/number-with-commas";

import { NotificationContext } from "../contexts/NotificationProvider";
import { useAppContext } from "../contexts/AppContext";

import "./Styles/Mint.scss";

export const Mint = () => {
  const DELAY = 60 * 60 * 8; // some buffer for allowance

  const { quid, sdai, addressQD, addressSDAI, account } = useAppContext();

  const [mintValue, setMintValue] = useState("");
  const inputRef = useRef(null);
  const buttonRef = useRef(null);
  const { notify } = useContext(NotificationContext);

  const [sdaiValue, setSdaiValue] = useState(0);
  const [totalSupplyCap, setTotalSupplyCap] = useState(0);
  const [totalSupply, setTotalSupply] = useState("");
  const [state, setState] = useState("idle");
  const [isSameBeneficiary, setIsSameBeneficiary] = useState(true);
  const [beneficiary, setBeneficiary] = useState("");
  const [isModalOpen, setIsModalOpen] = useState(false);

  const handleCloseModal = () => setIsModalOpen(false);

  const handleAgreeTerms = async () => {
    setIsModalOpen(false);
    localStorage.setItem("hasAgreedToTerms", "true");
    buttonRef?.current?.click();
  };

  const qdAmountToSdaiAmt = async (qdAmount, delay = 0) => {    
    const currentTimestamp = (Date.now() / 1000 + delay).toFixed(0);

    const currentTimestampBN = currentTimestamp.toString();
    const qdAmountBN = qdAmount.toString();

    const qdAmountCall = quid ? await quid.methods.qd_amt_to_dollar_amt(qdAmountBN, currentTimestampBN).call() : 0;

    return qdAmountCall;
  };

  useDebounce(
    mintValue,
    async () => {
      if (parseInt(mintValue) > 0) {
        const result = await qdAmountToSdaiAmt(mintValue, 18);
        setSdaiValue(parseFloat(formatUnits(result, 18)));
      } else {
        setSdaiValue(0);
      }
    },
    500
  );

  const updateTotalSupply = async (currentTimestamp, quid) => {
    if (quid) {
      console.log("effect working... ", quid);

      const currentTimestampBN = currentTimestamp.toString();

      Promise.all([
        await quid.methods.get_total_supply_cap(currentTimestampBN).call(),
        await quid.methods.totalSupply().call()
      ]).then(([totalSupplyCap, totalSupply]) => {
        const totalSupplyCapInt = parseInt(formatUnits(totalSupplyCap, 18));

        setTotalSupply(parseInt(formatUnits(totalSupply, 18)).toString());
        setTotalSupplyCap(totalSupplyCapInt);
      });
    }
  };

  useEffect(() => {
    const currentTimestamp = (Date.now() / 1000).toFixed(0);

    if (quid) updateTotalSupply(currentTimestamp, quid);

    const timerId = quid ? setInterval(updateTotalSupply, 5000) : setInterval(console.log("need quid"), 5000);

    return () => clearInterval(timerId);
  }, [quid, account]);

  const handleChangeValue = (e) => {
    const regex = /^\d*(\.\d*)?$|^$/;
    let originalValue = e.target.value;

    if (originalValue.length > 1 && originalValue[0] === "0" && originalValue[1] !== ".") {
      originalValue = originalValue.substring(1);
    }

    if (originalValue[0] === ".") {
      originalValue = "0" + originalValue;
    }

    if (regex.test(originalValue)) {
      setMintValue(Number(originalValue).toFixed(0));
    }
  };

  const handleSubmit = async (e) => {
    console.log("Form started: ", totalSupply);

    if (e) {
      e.preventDefault();
      console.log("preventDefault: ", e);
    }

    const beneficiaryAccount = !isSameBeneficiary && beneficiary !== "" ? beneficiary : account;

    const hasAgreedToTerms = localStorage.getItem("hasAgreedToTerms") === "true";

    if (!hasAgreedToTerms) {
      setIsModalOpen(true);
      return;
    }

    if (!isSameBeneficiary && beneficiary === "") {
      notify({
        severity: "error",
        message: "Please select a beneficiary"
      });
      return;
    }

    if (!account) {
      notify({
        severity: "error",
        message: "Please connect your wallet"
      });
      return;
    }

    if (!mintValue.length) {
      notify({
        severity: "error",
        message: "Please enter amount"
      });
      return;
    }

    if (+mintValue < 50) {
      notify({
        severity: "error",
        message: "The amount should be more than 50"
      });
      return;
    }

    if (+mintValue > totalSupplyCap) {
      notify({
        severity: "error",
        message: "The amount should be less than the maximum mintable QD"
      });
      return;
    }

    const balance = async () => {
      if (sdai) Number(formatUnits(await sdai.methods.balanceOf(account).call(), 18));
    };

    if (+sdaiValue > balance) {
      notify({
        severity: "error",
        message: "Cost shouldn't be more than your sDAI balance"
      });
      return;
    }

    try {
      setState("loading");
      const qdAmount = parseUnits(mintValue, 18);
      
      const sdaiAmount = await qdAmountToSdaiAmt(qdAmount, DELAY);

      const allowanceBigNumber = await sdai.methods.allowance(account, addressQD).call();

      const allowanceBigNumberBN = allowanceBigNumber.toString()
      const addresQDBN = addressQD.toString()

      console.log(
        "Start minting:",
        "\nCurrent allowance: ",
        formatUnits(allowanceBigNumberBN, 18),
        "\nNote amount: ",
        formatUnits(sdaiAmount.toString(), 18)
      );

      if (parseInt(formatUnits(allowanceBigNumberBN, 18)) !== 0) {
        setState("decreaseAllowance");

        await sdai.methods.decreaseAllowance(addresQDBN, allowanceBigNumberBN).send({ from: account });
      }

      setState("approving");

      await sdai.methods.approve(addressQD.toString(), sdaiAmount.toString()).send({ from: account });

      notify({
        severity: "success",
        message: "Please wait for approving",
        autoHideDuration: 4500
      });

      setState("minting");

      notify({
        severity: "success",
        message: "Please check your wallet"
      });

      const allowanceBeforeMinting = await sdai.methods.allowance(account, addressQD).call();

      console.log(
        "Start minting:",
        "\nQD amount: ",
        mintValue,
        "\nCurrent account: ",
        account,
        "\nAllowance: ",
        formatUnits(allowanceBeforeMinting, 18)
      );

      await quid.methods.deposit(beneficiaryAccount.toString(), qdAmount.toString(), addressSDAI.toString()).send({ from: account });

      console.log("MINTED: ", account);

      notify({
        severity: "success",
        message: "Your minting is pending!"
      });
    } catch (err) {
      console.error(err);
      var msg;
      let er = "MO::mint: supply cap exceeded";
      if (err.error?.message === er || err.message === er) {
        msg = "Please wait for more QD to become mintable...";
      } else {
        msg = err.error?.message || err.message;
      }
      notify({
        severity: "error",
        message: msg,
        autoHideDuration: 3200
      });
    } finally {
      setState("none");
      setMintValue("");
    }
  };

  const handleSetMaxValue = async () => {
    if (!account) {
      notify({
        message: "Please connect your wallet",
        severity: "error"
      });
      return;
    }

    const costOfOneQd = Number(formatUnits(await qdAmountToSdaiAmt("1"), 18));
    const balance = Number(formatUnits(await sdai.methods.balanceOf(account).call(), 18));
    const newValue = Number(totalSupplyCap) < balance ? totalSupplyCap : balance / costOfOneQd;

    setMintValue(Number(newValue).toFixed(0));

    if (inputRef) {
      inputRef.current?.focus();
    }

    if (mintValue) handleSubmit();
  };

  return (
    <form className="mint-root" onSubmit={handleSubmit}>
      <div>
        <div>
          <div className="mint-availability">
            <span className="mint-availabilityMax">
              <span style={{ color: "#02d802" }}>
                {numberWithCommas(totalSupplyCap.toFixed())}
                &nbsp;
              </span>
              QD mintable
            </span>
          </div>
          <div className="mint-inputContainer">
            <input
              type="text"
              id="mint-input"
              className="mint-input"
              value={mintValue}
              onChange={handleChangeValue}
              placeholder="Mint amount"
              ref={inputRef}
            />
            <label htmlFor="mint-input" className="mint-dollarSign">
              QD
            </label>
            <button className="mint-maxButton" onClick={handleSetMaxValue} type="button">
              Max
              <Icon preserveAspectRatio="none" className="mint-maxButtonBackground" name="btn-bg" />
            </button>
          </div>
          <div className="mint-sub">
            <div className="mint-subLeft">
              Cost in $
              <strong>
                {sdaiValue === 0 ? "sDAI Amount" : numberWithCommas(sdaiValue.toFixed())}
              </strong>
            </div>
            {mintValue ? (
              <div className="mint-subRight">
                <strong style={{ color: "#02d802" }}>
                  ${numberWithCommas((+mintValue - sdaiValue).toFixed())}
                </strong>
                Future profit
              </div>
            ) : null}
          </div>
          <button ref={buttonRef} type="submit" className="submit">
            {state !== "none" ? `...${state}` : "MINT"}
            <Icon preserveAspectRatio="none" className="mint-submitBtnL1" name="composite-btn-l1" />
            <Icon preserveAspectRatio="none" className="mint-submitBtnL2" name="composite-btn-l2" />
            <Icon preserveAspectRatio="none" className="mint-submitBtnL3" name="composite-btn-l3" />
            <div className="mint-glowEffect" />
          </button>
          <label style={{ position: "absolute", top: 165, right: -170 }}>
            <input
              name="isBeneficiary"
              className="mint-checkBox"
              type="checkbox"
              checked={isSameBeneficiary}
              onChange={(evt) => {
                setIsSameBeneficiary(!isSameBeneficiary);
              }}
            />
            <span className="mint-availabilityMax">to myself</span>
          </label>
        </div>
      </div>
      {isSameBeneficiary ? null : (
        <div className="mint-beneficiaryContainer">
          <div className="mint-inputContainer">
            <input
              name="beneficiary"
              type="text"
              className="mint-beneficiaryInput"
              onChange={(e) => setBeneficiary(e.target.value)}
              placeholder={account ? String(account) : ""}
            />
            <label htmlFor="mint-input" className="mint-idSign">
              beneficiary
            </label>
          </div>
        </div>
      )}
      <Modal open={isModalOpen} handleAgree={handleAgreeTerms} handleClose={handleCloseModal} />
    </form>
  );
};
