import React from 'react';
import { Swiper, SwiperSlide } from 'swiper/react';

import './MaintPage.scss';

const HomePage = () => {
  const [fromToken, setFromToken] = useState('BTC');
  const [toToken, setToToken] = useState('STBTC');
  const [amount, setAmount] = useState('');
  const [fees, setFees] = useState(0);
  const [estimatedReceived, setEstimatedReceived] = useState(0);
  const [provider, setProvider] = useState(null);
  const [signer, setSigner] = useState(null);
  const [account, setAccount] = useState('');
  const [modalIsOpen, setModalIsOpen] = useState(false);
  const [btcAddress, setBtcAddress] = useState('TODO');
  const [ethAddress, setEthAddress] = useState('TODO');
  const [btcTxHash, setBtcTxHash] = useState('TODO');
  const [signedMessage, setSignedMessage] = useState('TODO');
  const [modalType, setModalType] = useState('');

  const avsTaskManagerCreateTaskAbi = [
    {
      "inputs": [
        { "internalType": "string", "name": "btcTxHash", "type": "string" },
        { "internalType": "string", "name": "signedMessage", "type": "string" },
        { "internalType": "address", "name": "mintTo", "type": "address" },
        { "internalType": "uint256", "name": "burnAmount", "type": "uint256" },
        { "internalType": "string", "name": "btcDestinationAddress", "type": "string" },
        { "internalType": "bool", "name": "isBurnTask", "type": "bool" },
        { "internalType": "uint32", "name": "quorumThresholdPercentage", "type": "uint32" },
        { "internalType": "bytes", "name": "quorumNumbers", "type": "bytes" }
      ],
      "name": "createNewTask",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    }
  ];

  return (
    <React.Fragment>
      <Swiper
        /*onSwiper={(swiper) => setSwiperRef(swiper)}*/
        slidesPerView={1}
        direction={'vertical'}
        className="main-carousel"
        allowTouchMove={false}
      >
        <SwiperSlide className="main-slide">

          <div className="main-fakeCol" />

        

        </SwiperSlide>
      </Swiper>
    </React.Fragment>
  );
};

export default HomePage;
