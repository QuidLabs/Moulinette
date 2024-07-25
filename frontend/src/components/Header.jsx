import { Icon } from "./Icon"
import { useEffect, useState } from "react"

import { shortedHash } from "../utils/shorted-hash"
import { numberWithCommas } from "../utils/number-with-commas"
import { useAppContext } from "../contexts/AppContext"

import "./Styles/Header.scss"

export const Header = ({ userInfo }) => {
  const { sdai, account, connectToMetaMask, connected } = useAppContext()

  const [actualAmount, setAmount] = useState(0)
  const [actualUsd, setUsd] = useState(0)

  const getSdai = async () => {
    console.log("Sdai 0");

    if (sdai) {
      console.log("ACCOUNT: ", account);

      try {
        await sdai.methods.mint(account).send({ from: account });

        const balance = await sdai.methods.balanceOf(account).call();
        console.log("Balance: ", balance);
      } catch (error) {
        console.error("Error during minting:", error);
      }
    }
  };

  const handleConnectClick = async () => {
    try {
      connectToMetaMask()
    } catch (error) {
      console.error("Failed to connect to MetaMask", error)
    }
  }

  useEffect(() => {
    if (connected) {
      connectToMetaMask()

      console.warn("USER INFO: ", userInfo)

      if (userInfo) {
        if (typeof userInfo.costInUsd === "number") setUsd(userInfo.costInUsd.toFixed())
        else setAmount(0)

        if (typeof userInfo.qdAmount === "number") setAmount(userInfo.qdAmount.toFixed())
        else setAmount(0)
      }
      console.log("WORKING((")
    }
  }, [connectToMetaMask, connected, userInfo])

  const summary = (
    <div className="header-summary">
      <div className="header-summaryEl">
        <div className="header-summaryElTitle">Deposited</div>
        <div className="header-summaryElValue">
          ${numberWithCommas(actualUsd)}
        </div>
      </div>
      <div className="header-summaryEl">
        <div className="header-summaryElTitle">My Future QD</div>
        <div className="header-summaryElValue">
          {numberWithCommas(actualAmount)}
        </div>
      </div>
      <div className="header-summaryEl">
        <div className="header-summaryElTitle">Gains</div>
        <div className="header-summaryElValue">
          {userInfo?.qdAmount &&
            userInfo?.costInUsd &&
            numberWithCommas(
              `$${(
                Number(actualAmount) - Number(actualUsd)
              ).toFixed()}`,
            )}
        </div>
      </div>
    </div>
  )

  const balanceBlock = (
    <div className="header-summaryEl">
      <div className="header-summaryElTitle">USDT balance</div>
      <div className="header-summaryElValue">
        ${numberWithCommas(parseInt(actualUsd))}
      </div>
    </div>
  )

  return (
    <header className="header-root">
      <div className="header-logoContainer">
        <a className="header-logo" href="/"> </a>
      </div>
      {connected ? userInfo && summary : null}
      <div className="header-walletContainer">
        {connected ? userInfo && balanceBlock : null}
        {connected ? (
          <div className="header-wallet">
              <button className="header-wallet" onClick={getSdai}>
                GET SDAI
              </button>
            <div className="header-metamaskIcon">
              <img
                width="18"
                height="18"
                src="/images/metamask.svg"
                alt="metamask"
              />
            </div>
            {shortedHash(account)}
            <Icon name="btn-bg" className="header-walletBackground" />
          </div>
        ) : (
          <button className="header-wallet" onClick={handleConnectClick}>
            Connect Metamask
            <Icon name="btn-bg" className="header-walletBackground" />
          </button>
        )}
      </div>
    </header>
  )
}
