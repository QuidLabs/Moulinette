import { useCallback, useEffect, useState, useRef } from "react"
import { formatUnits, parseUnits } from "@ethersproject/units"

import { Modal } from "./Modal"
import { Icon } from "./Icon"

import { useDebounce } from "../utils/use-debounce"
import { numberWithCommas } from "../utils/number-with-commas"

import { useAppContext } from "../contexts/AppContext"

import "./Styles/Mint.scss"

export const Mint = () => {
  const DELAY = 60 * 60 * 8 

  const { getTotalInfo, getUserInfo, getTotalSupply,
    addressQD, addressSDAI, account, currentPrice, quid, sdai } = useAppContext()

  const [mintValue, setMintValue] = useState("")
  const [sdaiValue, setSdaiValue] = useState(0)
  const [totalSupplyCap, setTotalSupplyCap] = useState(0)
  const [state, setState] = useState("MINT")
  const [isSameBeneficiary, setIsSameBeneficiary] = useState(true)
  const [beneficiary, setBeneficiary] = useState("")
  const [isModalOpen, setIsModalOpen] = useState(false)

  const [notifications, setNotifications] = useState([]) 

  const inputRef = useRef(null)
  const buttonRef = useRef(null)

  const handleCloseModal = () => setIsModalOpen(false)

  const handleAgreeTerms = async () => {
    setIsModalOpen(false)
    localStorage.setItem("hasAgreedToTerms", "true")
    buttonRef?.current?.click()
  }

  const qdAmountToSdaiAmt = async (qdAmount, delay = 0) => {
    const currentTimestamp = (Date.now() / 1000 + delay).toFixed(0)

    const currentTimestampBN = currentTimestamp.toString()
    const qdAmountBN = qdAmount.toString()

    const qdAmountCall = quid
      ? await quid.methods.qd_amt_to_dollar_amt(qdAmountBN, currentTimestampBN).call()
      : 0

    return qdAmountCall
  }

  useDebounce(
    mintValue,
    async () => {
      if (parseInt(mintValue) > 0) setSdaiValue(currentPrice * 0.01)
      else setSdaiValue(0)
    },
    500
  )

  const updateTotalSupply = useCallback(async () => {
    try {
      if (quid) {
        const totalSupply = await getTotalSupply()

        setTotalSupplyCap(totalSupply)
      }
    } catch (error) {
      console.error(error)
      return null
    }
  }, [getTotalSupply, quid])
  

  useEffect(() => {
    if (quid) updateTotalSupply()
  }, [updateTotalSupply, quid])

  const handleChangeValue = (e) => {
    const regex = /^\d*(\.\d*)?$|^$/

    let originalValue = e.target.value

    if (originalValue.length > 1 && originalValue[0] === "0" && originalValue[1] !== ".")
      originalValue = originalValue.substring(1)

    if (originalValue[0] === ".") originalValue = "0" + originalValue

    if (regex.test(originalValue)) setMintValue(Number(originalValue).toFixed(0))
  }

  const handleSubmit = async (e) => {
    if (e) {
      e.preventDefault()
      console.log("preventDefault: ", e)
    }

    const beneficiaryAccount = !isSameBeneficiary && beneficiary !== "" ? beneficiary : account

    const hasAgreedToTerms = localStorage.getItem("hasAgreedToTerms") === "true"

    if (!hasAgreedToTerms) {
      setIsModalOpen(true)
      return
    }

    if (!isSameBeneficiary && beneficiary === "") {
      setNotifications([{ severity: "error", message: "Please select a beneficiary" }]) 
      return
    }

    if (!account) {
      setNotifications([{ severity: "error", message: "Please connect your wallet" }]) 
      return
    }

    if (!mintValue.length) {
      setNotifications([{ severity: "error", message: "Please enter amount" }]) 
      return
    }

    if (+mintValue < 50) {
      setNotifications([{ severity: "error", message: "The amount should be more than 50" }]) 
      return
    }

    if (+mintValue > totalSupplyCap) {
      setNotifications([{ severity: "error", message: "The amount should be less than the maximum mintable QD" }]) 
      return
    }

    const balance = async () => {
      if (sdai) return Number(formatUnits(await sdai.methods.balanceOf(account).call(), 18))
    }

    if (+sdaiValue > (await balance())) {
      setNotifications([{ severity: "error", message: "Cost shouldn't be more than your sDAI balance" }]) 
      return
    }

    try {
      const qdAmount = parseUnits(mintValue, 18)

      setState("loading")
      setMintValue("")

      const sdaiAmount = await qdAmountToSdaiAmt(qdAmount, DELAY)

      const allowanceBigNumber = await sdai.methods.allowance(account, addressQD).call()

      const allowanceBigNumberBN = allowanceBigNumber.toString()
      const addresQDBN = addressQD.toString()

      console.log(
        "Start minting:",
        "\nCurrent allowance: ",
        formatUnits(allowanceBigNumberBN, 18),
        "\nNote amount: ",
        formatUnits(sdaiAmount.toString(), 18)
      )

      if (parseInt(formatUnits(allowanceBigNumberBN, 18)) !== 0) {
        setState("decreaseAllowance")

        await sdai.methods.decreaseAllowance(addresQDBN, allowanceBigNumberBN).send({ from: account })
      }

      setState("approving")

      await sdai.methods.approve(addressQD.toString(), sdaiAmount.toString()).send({ from: account })

      setNotifications([{ severity: "success", message: "Please wait for approving" }]) 

      setState("minting")

      setNotifications([{ severity: "success", message: "Please check your wallet" }]) 

      const allowanceBeforeMinting = await sdai.methods.allowance(account, addressQD).call()

      console.log(
        "Start minting:",
        "\nQD amount: ",
        mintValue,
        "\nCurrent account: ",
        account,
        "\nAllowance: ",
        formatUnits(allowanceBeforeMinting, 18)
      )

      await quid.methods.deposit(beneficiaryAccount.toString(), qdAmount.toString(), addressSDAI.toString()).send({ from: account })

      await getTotalInfo()
      await getUserInfo()

      console.log("MINTED: ", account)

      setNotifications([{ severity: "success", message: "Your minting is pending!" }]) 
    } catch (err) {
      console.error(err)
      var msg
      let er = "MO::mint: supply cap exceeded"
      if (err.error?.message === er || err.message === er) {
        msg = "Please wait for more QD to become mintable..."
      } else {
        msg = err.error?.message || err.message
      }
      setNotifications([{ severity: "error", message: msg }]) 
    } finally {
      setState("none")
      setMintValue("")
    }
  }

  const handleSetMaxValue = async () => {
    if (!account) {
      setNotifications([{ message: "Please connect your wallet", severity: "error" }]) 
      return
    }

    const costOfOneQd = Number(formatUnits(await qdAmountToSdaiAmt("1"), 18))
    const balance = Number(formatUnits(await sdai.methods.balanceOf(account).call(), 18))
    const newValue = Number(totalSupplyCap) < balance ? totalSupplyCap : balance / costOfOneQd

    setMintValue(Number(newValue).toFixed(0))

    if (inputRef) inputRef.current?.focus()

    if (mintValue) handleSubmit()
  }

  return (
    <form className="mint-root" onSubmit={handleSubmit}>
      <div className="mint-availability">
        <span className="mint-availabilityMax">
          <span style={{ color: "#02d802" }}>
            {numberWithCommas(totalSupplyCap)}
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
            {sdaiValue === 0 ? "sDAI Amount" : numberWithCommas(parseFloat(sdaiValue))}
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
      <button ref={buttonRef} type="submit" className="mint-submit">
        {state !== "none" ? `${state}` : "MINT"}
        <div className="mint-glowEffect" />
      </button>
      <label style={{ position: "absolute", top: 165, right: -170 }}>
        <input
          name="isBeneficiary"
          className="mint-checkBox"
          type="checkbox"
          checked={isSameBeneficiary}
          onChange={(evt) => {
            setIsSameBeneficiary(!isSameBeneficiary)
          }}
        />
        <span className="mint-availabilityMax">to myself</span>
      </label>
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
      <div className="mint-notifications">
        {notifications.map((notification, index) => (
          <div
            key={index}
            className={`mint-notification ${notification.severity}`}
          >
            {notification.message}
          </div>
        ))}
      </div>
      <Modal open={isModalOpen} handleAgree={handleAgreeTerms} handleClose={handleCloseModal} />
    </form>
  )
}
