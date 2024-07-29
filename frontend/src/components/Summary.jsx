
import { useEffect, useState, useCallback } from "react"
import { useAppContext } from "../contexts/AppContext";
import { numberWithCommas } from "../utils/number-with-commas"

import "./Styles/Summary.scss"

export const Summary = () => {
  const { getSales, getUserInfo, connected, currentTimestamp, quid, sdai, 
    account, addressQD, SECONDS_IN_DAY } = useAppContext();

  const [smartContractStartTimestamp, setSmartContractStartTimestamp] = useState("")
  const [mintPeriodDays, setMintPeriodDays] = useState("")
  const [totalDeposited, setTotalDeposited] = useState("")
  const [totalMinted, setTotalMinted] = useState("")
  const [price, setPrice] = useState("")

  const updatingInfo = useCallback(async () => {
    try {
      if (quid && sdai && addressQD) {
        const updatedInfo = await getUserInfo()
        const updatedSales = await getSales()
        
        if (updatedInfo) {
          setTotalDeposited(updatedInfo.actualUsd)
          setTotalMinted(updatedInfo.actualQD)
          setPrice(updatedInfo.price)
        }
  
        setMintPeriodDays(updatedSales.mintPeriodDays)
        setSmartContractStartTimestamp(updatedSales.smartContractStartTimestamp)
      }
    } catch (error) {
      console.error("Some problem with updateInfo, Summary.js, l.22: ", error)
    }
  }, [addressQD, sdai, quid, getSales, getUserInfo])
  
  useEffect(() => {
    try{
      if(connected) updatingInfo()
    } catch (error) {
      console.error("Some problem with sale's start function: ", error)
    }
  }, [updatingInfo, connected, account, totalMinted])

  const daysLeft = smartContractStartTimestamp ? (
    Math.max(
      Math.ceil(
        Number(mintPeriodDays) -
        (Number(currentTimestamp) - Number(smartContractStartTimestamp)) /
        SECONDS_IN_DAY
      ),
      0
    )
  ) : (
    <>&nbsp;</>
  )
  return (
    <div className="summary-root">
    <div className="summary-section">
      <div className="summary-title">Days left</div>
      <div className="summary-value">{daysLeft}</div>
    </div>
    <div className="summary-section">
      <div className="summary-title">Current price</div>
      <div className="summary-value">
        <span className="summary-value">{Number(price).toFixed(0)}</span>
        <span className="summary-cents"> Cents</span>
      </div>
    </div>
    <div className="summary-section">
      <div className="summary-title">sDAI Deposited</div>
      <div className="summary-value">
        ${numberWithCommas(parseFloat(String(Number(totalDeposited))).toFixed())}
      </div>
    </div>
    <div className="summary-section">
      <div className="summary-title">Minted QD</div>
      <div className="summary-value">
        {numberWithCommas(parseFloat(Number(totalMinted).toFixed(1)))}
      </div>
    </div>
  </div>
  )  
}
