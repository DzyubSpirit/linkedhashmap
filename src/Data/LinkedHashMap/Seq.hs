{-# LANGUAGE BangPatterns #-}
module Data.LinkedHashMap.Seq 
    (
      LinkedHashMap(..)

      -- * Construction
    , empty
    , singleton

      -- * Basic interface
    , null
    , size
    , member
    , lookup
    , lookupDefault
    , (!)
    , insert
    , insertWith
    , delete
    , adjust

      -- * Combine
      -- ** Union
    , union
    , unionWith
    , unions

      -- * Transformations
    , map
    , mapWithKey
    , traverseWithKey

      -- * Difference and intersection
    -- , difference
    -- , intersection
    -- , intersectionWith

      -- * Folds
    -- , foldl'
    -- , foldlWithKey'
    , foldr
    -- , foldrWithKey

      -- * Filter
    -- , filter
    -- , filterWithKey

      -- * Conversions
    , keys
    , elems

      -- ** Lists
    , toList
    , fromList
    -- , fromListWith
    , pack
    ) where

import Prelude hiding (foldr, map, null, lookup)
import Data.Maybe
import Control.Applicative ((<$>), Applicative(pure))
import Control.DeepSeq (NFData(rnf))
import Data.Hashable (Hashable)
import Data.Sequence (Seq, (|>)) 
import Data.Traversable (Traversable(..))
import qualified Data.Sequence as S
import qualified Data.Foldable as F
import qualified Data.Traversable as T
import qualified Data.List as L
import qualified Data.HashMap.Strict as M

newtype Entry a = Entry { unEntry :: (Int, a) } deriving (Show)

instance Eq a => Eq (Entry a) where
    (Entry (_, a)) == (Entry (_, b)) = a == b

-- Contains HashMap, ordered keys Seq and number of not deleted keys in a sequence (size of HashMap)
data LinkedHashMap k v = LinkedHashMap (M.HashMap k (Entry v)) (Seq (Maybe (k, v))) !Int

instance (Show k, Show v) => Show (LinkedHashMap k v) where
    showsPrec d m@(LinkedHashMap _ _ _) = showParen (d > 10) $
      showString "fromList " . shows (toList m)

-- | /O(log n)/ Return the value to which the specified key is mapped,
-- or 'Nothing' if this map contains no mapping for the key.
lookup :: (Eq k, Hashable k) => k -> LinkedHashMap k v -> Maybe v
lookup k0 (LinkedHashMap m0 _ _) = case M.lookup k0 m0 of
                                     Just (Entry (_, v)) -> Just v
                                     Nothing -> Nothing
{-# INLINABLE lookup #-}

-- | /O(n*log n)/ Construct a map with the supplied mappings.  If the
-- list contains duplicate mappings, the later mappings take
-- precedence.
fromList :: (Eq k, Hashable k) => [(k, v)] -> LinkedHashMap k v
fromList ps = LinkedHashMap m' s' len'
  where
    m0 = M.fromList $ L.map (\(i, (k, v)) -> (k, Entry (i, v))) $ zip [0..] ps
    s0 = S.fromList $ L.map (\(k, v) -> Just (k, v)) ps
    len = M.size m0
    (m', s', len') = if len == S.length s0
                     then (m0, s0, len)
                     else F.foldl' skipDups (m0, S.empty, 0) s0
    skipDups (m, s, n) jkv@(Just (k, _)) 
      | n == ix = (m, s |> jkv, n + 1)
      | n > ix = (m, s, n)
      | otherwise = (M.insert k (Entry (n, v)) m, s |> Just (k, v), n + 1)
      where 
        (ix, v) = unEntry $ fromJust $ M.lookup k m
    skipDups _ _ = error "Data.LinkedHashMap.Seq invariant violated"

-- | /O(n)/ Return a list of this map's elements.  The list is produced lazily.
toList ::LinkedHashMap k v -> [(k, v)]
toList (LinkedHashMap _ s _) = catMaybes (F.toList s)
{-# INLINABLE toList #-}

-- | /O(log n)/ Associate the specified value with the specified
-- key in this map.  If this map previously contained a mapping for
-- the key, the old value is replaced.
insert :: (Eq k, Hashable k) => k -> v -> LinkedHashMap k v -> LinkedHashMap k v
insert k !v (LinkedHashMap m s n) = LinkedHashMap m' s' n'
  where 
    m' = M.insert k (Entry (ix', v)) m
    (s', ix', n') = case M.lookup k m of
                      Just (Entry (ix, _)) -> (s, ix, n)
                      Nothing -> (s |> Just (k, v), S.length s, n+1)
{-# INLINABLE insert #-}

pack :: (Eq k, Hashable k) => LinkedHashMap k v -> LinkedHashMap k v
pack = fromList . toList

-- | /O(log n)/ Remove the mapping for the specified key from this map
-- if present.
delete :: (Eq k, Hashable k) => k -> LinkedHashMap k v -> LinkedHashMap k v
delete k0 (LinkedHashMap m s n) = if S.length s `div` 2 >= n 
                                  then pack lhm 
                                  else lhm
  where
    lhm = LinkedHashMap m' s' n'
    (m', s', n') = case M.lookup k0 m of
                     Nothing -> (m, s, n)
                     Just (Entry (i, _)) -> (M.delete k0 m, S.update i Nothing s, n-1)
                                           
-- | /O(1)/ Construct an empty map.
empty :: LinkedHashMap k v
empty = LinkedHashMap M.empty S.empty 0

-- | /O(1)/ Construct a map with a single element.
singleton :: (Eq k, Hashable k) => k -> v -> LinkedHashMap k v
singleton k v = fromList [(k, v)]

-- | /O(1)/ Return 'True' if this map is empty, 'False' otherwise.
null :: LinkedHashMap k v -> Bool
null (LinkedHashMap m _ _) = M.null m

-- | /O(log n)/ Return 'True' if the specified key is present in the
-- map, 'False' otherwise.
member :: (Eq k, Hashable k) => k -> LinkedHashMap k a -> Bool
member k m = case lookup k m of
    Nothing -> False
    Just _  -> True
{-# INLINABLE member #-}

-- | /O(1)/ Return the number of key-value mappings in this map.
size :: LinkedHashMap k v -> Int
size (LinkedHashMap _ _ n) = n

-- | /O(log n)/ Return the value to which the specified key is mapped,
-- or the default value if this map contains no mapping for the key.
lookupDefault :: (Eq k, Hashable k)
              => v          -- ^ Default value to return.
              -> k -> LinkedHashMap k v -> v
lookupDefault def k t = case lookup k t of
    Just v -> v
    _      -> def
{-# INLINABLE lookupDefault #-}

-- | /O(log n)/ Return the value to which the specified key is mapped.
-- Calls 'error' if this map contains no mapping for the key.
(!) :: (Eq k, Hashable k) => LinkedHashMap k v -> k -> v
(!) m k = case lookup k m of
    Just v  -> v
    Nothing -> error "Data.LinkedHashMap.Seq.(!): key not found"
{-# INLINABLE (!) #-}

-- | /O(n)/ Return a list of this map's keys.  The list is produced
-- lazily.
keys :: (Eq k, Hashable k) => LinkedHashMap k v -> [k]
keys m = L.map (\(k, _) -> k) $ toList m
{-# INLINE keys #-}

-- | /O(n)/ Return a list of this map's values.  The list is produced
-- lazily.
elems :: (Eq k, Hashable k) => LinkedHashMap k v -> [v]
elems m = L.map (\(_, v) -> v) $ toList m
{-# INLINE elems #-}

-- | /O(log n)/ Associate the value with the key in this map.  If
-- this map previously contained a mapping for the key, the old value
-- is replaced by the result of applying the given function to the new
-- and old value.  Example:
--
-- > insertWith f k v map
-- >   where f new old = new + old
insertWith :: (Eq k, Hashable k) => (v -> v -> v) -> k -> v -> LinkedHashMap k v -> LinkedHashMap k v
insertWith f k v (LinkedHashMap m s n) = LinkedHashMap m' s' n'
  where
    m' = M.insertWith f' k v' m
    f' (Entry (_, v1)) (Entry (ix, v2)) = Entry (ix, f v1 v2)
    slen = S.length s
    v' = Entry (slen, v)
    (ixnew, vnew) = unEntry $ fromJust $ M.lookup k m'
    (s', n') = if ixnew == slen 
               then (s |> Just (k, vnew), n + 1)
               else (S.update ixnew (Just (k, vnew)) s, n)

-- | /O(log n)/ Adjust the value tied to a given key in this map only
-- if it is present. Otherwise, leave the map alone.
adjust :: (Eq k, Hashable k) => (v -> v) -> k -> LinkedHashMap k v -> LinkedHashMap k v
adjust f k (LinkedHashMap m s n) = LinkedHashMap m' s' n
  where
    m' = M.adjust f' k m
    f' (Entry (ix, v)) = Entry (ix, f v)
    s' = case M.lookup k m' of
           Just (Entry (ix, v)) -> S.update ix (Just (k, v)) s
           Nothing -> s

-- | /O(m*log n)/ The union of two maps, n - size of first map. If a key occurs in both maps, the
-- mapping from the first will be the mapping in the result.
union :: (Eq k, Hashable k) => LinkedHashMap k v -> LinkedHashMap k v -> LinkedHashMap k v
union = unionWith const
{-# INLINABLE union #-}

-- | /O(m*log n)/ The union of two maps.  If a key occurs in both maps,
-- the provided function (first argument) will be used to compute the
-- result.
unionWith :: (Eq k, Hashable k) => (v -> v -> v) -> LinkedHashMap k v -> LinkedHashMap k v
          -> LinkedHashMap k v
unionWith f m1 m2 = m'
  where
    m' = F.foldl' (\m (k, v) -> insertWith (flip f) k v m) m1 $ toList m2

-- | Construct a set containing all elements from a list of sets.
unions :: (Eq k, Hashable k) => [LinkedHashMap k v] -> LinkedHashMap k v
unions = F.foldl' union empty
{-# INLINE unions #-}

-- | /O(n)/ Transform this map by applying a function to every value.
map :: (v1 -> v2) -> LinkedHashMap k v1 -> LinkedHashMap k v2
map f = mapWithKey (const f)
{-# INLINE map #-}

-- | /O(n)/ Transform this map by applying a function to every value.
mapWithKey :: (k -> v1 -> v2) -> LinkedHashMap k v1 -> LinkedHashMap k v2
mapWithKey f (LinkedHashMap m s n) = (LinkedHashMap m' s' n)
  where
    m' = M.mapWithKey f' m
    s' = fmap f'' s
    f' k (Entry (ix, v1)) = Entry (ix, f k v1)
    f'' (Just (k, v1)) = Just (k, f k v1)
    f'' _  = Nothing

-- | /O(n*log(n))/ Transform this map by accumulating an Applicative result
-- from every value.
traverseWithKey :: Applicative f => (k -> v1 -> f v2) -> LinkedHashMap k v1
                -> f (LinkedHashMap k v2)
traverseWithKey f (LinkedHashMap m0 s0 n) = (\s -> LinkedHashMap (M.map (getV2 s) m0) s n) <$> s'
  where
    s' = T.traverse f' s0
    f' (Just (k, v1)) = (\v -> Just (k, v)) <$> f k v1
    f' Nothing = pure Nothing
    getV2 s (Entry (ix, _)) = let (_, v2) = fromJust $ S.index s ix in Entry (ix, v2)
{-# INLINE traverseWithKey #-}

instance (NFData a) => NFData (Entry a) where
    rnf (Entry a) = rnf a

instance (NFData k, NFData v) => NFData (LinkedHashMap k v) where
    rnf (LinkedHashMap m s _) = rnf m `seq` rnf s

instance Functor (LinkedHashMap k) where
    fmap = map

instance F.Foldable (LinkedHashMap k) where
    foldr f b0 (LinkedHashMap _ s _) = F.foldr f' b0 s
      where
        f' (Just (_, v)) b = f v b
        f' _ b = b
        
instance T.Traversable (LinkedHashMap k) where
    traverse f = traverseWithKey (const f)

-- | /O(n)/ Reduce this map by applying a binary operator to all
-- elements, using the given starting value (typically the
-- right-identity of the operator).
foldr :: (v -> a -> a) -> a -> LinkedHashMap k v -> a
foldr = F.foldr
{-# INLINE foldr #-}

