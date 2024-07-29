import { createContext, useState, useContext, useCallback } from "react"
import { useSDK } from "@metamask/sdk-react"
import { formatUnits, parseUnits } from "@ethersproject/units"
import { BigNumber } from "@ethersproject/bignumber"

import Web3 from "web3"

import { QUID, SDAI, addressQD, addressSDAI } from "../utils/constant"

const contextState = {
  account: "",
  connectToMetaMask: () => { },
  getSdai: () => { },
  getSales: () => { },
  getTotalInfo: () => { },
  getUserInfo: () => { },
  connected: false,
  connecting: false,
  provider: {},
  sdk: {},
  web3: {}
}

const AppContext = createContext(contextState)

export const AppContextProvider = ({ children }) => {
  const [account, setAccount] = useState("")
  const { sdk, connected, connecting, provider } = useSDK()

  const [quid, setQuid] = useState(null)
  const [sdai, setSdai] = useState(null)

  const [QDbalance, setQdBalance] = useState(null)
  const [SDAIbalance, setSdaiBalance] = useState(null)

  const [UsdBalance, setUsdBalance] = useState(null)
  const [localMinted, setLocalMinted] = useState(null)

  const [totalDeposite, setTotalDeposited] = useState("")
  const [totalMint, setTotalMinted] = useState("")
  const [currentTimestamp, setAccountTimestamp] = useState(0)

  const [currentPrice, setPrice] = useState(null)

  const SECONDS_IN_DAY = 86400

  const getSales = useCallback(async () => {
    try {
      if (quid && sdai && addressQD) {
        const days = await quid.methods.DAYS().call()
        const startDate = await quid.methods.START_DATE().call()

        const salesInfo = {
          mintPeriodDays: String(Number(days) / SECONDS_IN_DAY),
          smartContractStartTimestamp: startDate.toString()
        }

        return salesInfo
      }
      return null
    } catch (error) {
      console.error("Some problem with updateInfo, Summary.js, l.22: ", error)
      return null
    }
  }, [sdai, quid])

  const getTotalInfo = useCallback(async () => {
    try {
      setAccountTimestamp((Date.now() / 1000).toFixed(0))

      if (quid && sdai && addressQD) {
        const qdAmount = parseUnits("1", 18).toBigInt()

        const data = await quid.methods.qd_amt_to_dollar_amt(qdAmount, currentTimestamp).call()

        const value = Number(formatUnits(data, 18) * 100)

        const bigNumber = BigNumber.from(Math.floor(value).toString())

        const totalSupply = await quid.methods.totalSupply().call()
        const formattedTotalMinted = formatUnits(totalSupply, 18).split(".")[0]

        if (totalMint !== formattedTotalMinted) setTotalMinted(formattedTotalMinted)

        const balance = await sdai.methods.balanceOf(addressQD).call()
        const formattedTotalDeposited = formatUnits(balance, 18)

        if (totalDeposite !== formattedTotalDeposited) setTotalDeposited(formattedTotalDeposited)

        if (formattedTotalDeposited && formattedTotalMinted && bigNumber) {
          return { total_dep: formattedTotalDeposited, total_mint: formattedTotalMinted, price: bigNumber.toString() }
        }
      }
    } catch (error) {
      console.error("Error in updateInfo: ", error)
    }
  }, [quid, sdai, currentTimestamp, totalMint, totalDeposite])

  const getUserInfo = useCallback(async () => {
    try {
      setAccountTimestamp((Date.now() / 1000).toFixed(0))

      if (account && quid) {

        const qdAmount = parseUnits("1", 18).toBigInt()

        const data = await quid.methods.qd_amt_to_dollar_amt(qdAmount, currentTimestamp).call()

        const value = Number(formatUnits(data, 18) * 100)

        const bigNumber = BigNumber.from(Math.floor(value).toString())

        const info = await quid.methods.get_info(account).call()
        const actualUsd = Number(info[0]) / 1e18
        const actualQD = Number(info[1]) / 1e18

        setPrice(bigNumber.toString())
        setUsdBalance(actualUsd)
        setLocalMinted(actualQD) 

        return { actualUsd: actualUsd, actualQD: actualQD, price: bigNumber.toString(), info: info }
      }
    } catch (error) {
      console.warn(`Failed to get account info:`, error)
      return null
    }
  }, [quid, account, currentTimestamp])

  const getSdai = useCallback(async () => {
    try {
      console.log("Sdai 0")

      if (sdai) {
        await sdai.methods.mint(account).send({ from: account })

        console.log("ACCOUNT: ", account)
      }
    } catch (error) {
      console.warn(`Failed to connect:`, error)
    }
  }, [sdai, account])

  const getSdaiBalance = useCallback(async () => {
    try {
      if (sdai && account) {
        const balance = await sdai.methods.balanceOf(account).call()

        setSdaiBalance(parseFloat(balance) / 1e18)
      }
    } catch (error) {
      console.warn(`Failed to connect:`, error)
    }
  }, [account, sdai])

  const getQdBalance = useCallback(async () => {
    try {
      if (quid && account) {
        const balance = await quid.methods.balanceOf(account).call()

        setQdBalance(parseFloat(balance) / 1e18)
      }
    } catch (error) {
      console.warn(`Failed to connect:`, error)
    }
  }, [account, quid])

  const connectToMetaMask = useCallback(async () => {
    try {
      if (!account) {
        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' })
        setAccount(accounts?.[0])
  
        if (provider) {
          const web3Instance = new Web3(provider)
          const quidContract = new web3Instance.eth.Contract(QUID, addressQD)
          const sdaiContract = new web3Instance.eth.Contract(SDAI, addressSDAI)
  
          setQuid(quidContract)
          setSdai(sdaiContract)
        }
      }
  
      if (quid && sdai && account) {
        getSdaiBalance()
        getQdBalance()
      }
    } catch (error) {
      console.warn(`Failed to connect:`, error)
    }
  }, [getSdaiBalance, getQdBalance, account, provider, quid, sdai])
  

  return (
    <AppContext.Provider
      value={{
        account,
        connectToMetaMask,
        getSdai,
        getTotalInfo,
        getUserInfo,
        getSales,
        connected,
        connecting,
        currentTimestamp,
        provider,
        sdk,
        quid,
        sdai,
        QDbalance,
        SDAIbalance,
        addressQD,
        addressSDAI,
        currentPrice,
        UsdBalance,
        localMinted,
        totalDeposite,
        totalMint,
        SECONDS_IN_DAY
      }}
    >
      {children}
    </AppContext.Provider>
  )
}

export const useAppContext = () => useContext(AppContext)

export default AppContext
