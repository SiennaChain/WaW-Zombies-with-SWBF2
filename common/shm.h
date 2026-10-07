// Opens (or creates) the shared block. Either game may start first: whoever
// gets there first initialises the header, the other just validates it.
#pragma once

#include "wawbf_protocol.h"

namespace wawbf {

class SharedMapping {
 public:
  SharedMapping() = default;
  ~SharedMapping();
  SharedMapping(const SharedMapping&) = delete;
  SharedMapping& operator=(const SharedMapping&) = delete;

  // Logs and returns false on failure (e.g. protocol version mismatch).
  bool Open(Side self);
  void Close();

  SharedBlock* block() const { return block_; }

  void Beat();
  bool PeerAlive() const;

 private:
  void* handle_ = nullptr;
  SharedBlock* block_ = nullptr;
  Side self_ = kSideWaw;
};

}  // namespace wawbf
