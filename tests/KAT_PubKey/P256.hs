{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
module KAT_PubKey.P256 (tests) where

import qualified Crypto.PubKey.ECC.Types as ECC
import qualified Crypto.PubKey.ECC.Prim as ECC
import qualified Crypto.PubKey.ECC.P256 as P256

import           Data.ByteArray (Bytes)
import           Crypto.Number.Serialize (i2ospOf, os2ip)
import           Crypto.Number.ModArithmetic (inverseCoprimes)
import           Crypto.Error

import           Imports

newtype P256Scalar = P256Scalar Integer
    deriving (Show,Eq,Ord)

instance Arbitrary P256Scalar where
    arbitrary = P256Scalar . getQAInteger <$> arbitrary

curve  = ECC.getCurveByName ECC.SEC_p256r1
curveN = ECC.ecc_n . ECC.common_curve $ curve
curveGen = ECC.ecc_g . ECC.common_curve $ curve

pointP256ToECC :: P256.Point -> ECC.Point
pointP256ToECC = uncurry ECC.Point . P256.pointToIntegers

unP256Scalar :: P256Scalar -> P256.Scalar
unP256Scalar (P256Scalar r') =
    let r = if r' == 0 then 0x2901 else (r' `mod` curveN)
        rBytes = i2ospScalar r
     in case P256.scalarFromBinary rBytes of
                    CryptoFailed err    -> error ("cannot convert scalar: " ++ show err)
                    CryptoPassed scalar -> scalar
  where
    i2ospScalar :: Integer -> Bytes
    i2ospScalar i =
        case i2ospOf 32 i of
            Nothing -> error "invalid size of P256 scalar"
            Just b  -> b

unP256 :: P256Scalar -> Integer
unP256 (P256Scalar r') = if r' == 0 then 0x2901 else (r' `mod` curveN)

p256ScalarToInteger :: P256.Scalar -> Integer
p256ScalarToInteger s = os2ip (P256.scalarToBinary s :: Bytes)

xS = 0xde2444bebc8d36e682edd27e0f271508617519b3221a8fa0b77cab3989da97c9
yS = 0xc093ae7ff36e5380fc01a5aad1e66659702de80f53cec576b6350b243042a256
xT = 0x55a8b00f8da1d44e62f6b3b25316212e39540dc861c89575bb8cf92e35e0986b
yT = 0x5421c3209c2d6c704835d82ac4c3dd90f61a8a52598b9e7ab656e9d8c8b24316
xR = 0x72b13dd4354b6b81745195e98cc5ba6970349191ac476bd4553cf35a545a067e
yR = 0x8d585cbb2e1327d75241a8a122d7620dc33b13315aa5c9d46d013011744ac264

tests = testGroup "P256"
    [ testGroup "scalar"
        [ testProperty "marshalling" $ \(QAInteger r') ->
            let r = r' `mod` curveN
                rBytes = i2ospScalar r
             in case P256.scalarFromBinary rBytes of
                    CryptoFailed err    -> error (show err)
                    CryptoPassed scalar -> rBytes `propertyEq` P256.scalarToBinary scalar
        , testProperty "add" $ \r1 r2 ->
            let r = (unP256 r1 + unP256 r2) `mod` curveN
                r' = P256.scalarAdd (unP256Scalar r1) (unP256Scalar r2)
             in r `propertyEq` p256ScalarToInteger r'
        , testProperty "add0" $ \r ->
            let v = unP256 r
                v' = P256.scalarAdd (unP256Scalar r) P256.scalarZero
             in v `propertyEq` p256ScalarToInteger v'
        , testProperty "add-n-1" $ \r ->
            let nm1 = throwCryptoError $ P256.scalarFromInteger (curveN - 1)
                v   = unP256 r
                v'  = P256.scalarAdd (unP256Scalar r) nm1
             in (((curveN - 1) + v) `mod` curveN) `propertyEq` p256ScalarToInteger v'
        , testProperty "sub" $ \r1 r2 ->
            let r = (unP256 r1 - unP256 r2) `mod` curveN
                r' = P256.scalarSub (unP256Scalar r1) (unP256Scalar r2)
                v = (unP256 r2 - unP256 r1) `mod` curveN
                v' = P256.scalarSub (unP256Scalar r2) (unP256Scalar r1)
             in propertyHold
                    [ eqTest "r1-r2" r (p256ScalarToInteger r')
                    , eqTest "r2-r1" v (p256ScalarToInteger v')
                    ]
        , testProperty "sub-n-1" $ \r ->
            let nm1 = throwCryptoError $ P256.scalarFromInteger (curveN - 1)
                v = unP256 r
                v' = P256.scalarSub (unP256Scalar r) nm1
             in ((v - (curveN - 1)) `mod` curveN) `propertyEq` p256ScalarToInteger v'
        , testProperty "inv" $ \r' ->
            let inv  = inverseCoprimes (unP256 r') curveN
                inv' = P256.scalarInv (unP256Scalar r')
             in if unP256 r' == 0 then True else inv `propertyEq` p256ScalarToInteger inv'
        ]
    , testGroup "point"
        [ testProperty "marshalling" $ \rx ry ->
            let p = P256.pointFromIntegers (unP256 rx, unP256 ry)
                b = P256.pointToBinary p :: Bytes
                p' = P256.pointFromBinary b
             in propertyHold [ eqTest "point" (CryptoPassed p) p' ]
        , testProperty "marshalling-integer" $ \rx ry ->
            let p = P256.pointFromIntegers (unP256 rx, unP256 ry)
                (x,y) = P256.pointToIntegers p
             in propertyHold [ eqTest "x" (unP256 rx) x, eqTest "y" (unP256 ry) y ]
        , testCase "valid-point-1" $ casePointIsValid (xS,yS)
        , testCase "valid-point-2" $ casePointIsValid (xR,yR)
        , testCase "valid-point-3" $ casePointIsValid (xT,yT)
        , testCase "point-add-1" $
            let s = P256.pointFromIntegers (xS, yS)
                t = P256.pointFromIntegers (xT, yT)
                r = P256.pointFromIntegers (xR, yR)
             in r @=? P256.pointAdd s t
        , testProperty "lift-to-curve" $ propertyLiftToCurve
        , testProperty "point-add" $ propertyPointAdd
        ]
    ]
  where
    casePointIsValid pointTuple =
        let s = P256.pointFromIntegers pointTuple in True @=? P256.pointIsValid s

    propertyLiftToCurve r =
        let p     = P256.toPoint (unP256Scalar r)
            (x,y) = P256.pointToIntegers p
            pEcc  = ECC.pointMul curve (unP256 r) curveGen
         in pEcc `propertyEq` ECC.Point x y

    propertyPointAdd r1 r2 =
        let p1    = P256.toPoint (unP256Scalar r1)
            p2    = P256.toPoint (unP256Scalar r2)
            pe1   = ECC.pointMul curve (unP256 r1) curveGen
            pe2   = ECC.pointMul curve (unP256 r2) curveGen
            pR    = P256.toPoint (P256.scalarAdd (unP256Scalar r1) (unP256Scalar r2))
            peR   = ECC.pointAdd curve pe1 pe2
            (x,y) = P256.pointToIntegers (P256.pointAdd p1 p2) -- P256.pointToIntegers pR
         in propertyHold [ eqTest "p256" pR (P256.pointAdd p1 p2)
                         , eqTest "ecc" peR (pointP256ToECC pR)
                         ]

    i2ospScalar :: Integer -> Bytes
    i2ospScalar i =
        case i2ospOf 32 i of
            Nothing -> error "invalid size of P256 scalar"
            Just b  -> b