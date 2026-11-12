//! Every Premiumize API path, relative to `Options.base_url`.

pub const account = struct {
    pub const info = "/account/info";
};

pub const folder = struct {
    pub const list = "/folder/list";
    pub const create = "/folder/create";
    pub const rename = "/folder/rename";
    pub const paste = "/folder/paste";
    pub const delete = "/folder/delete";
    pub const uploadinfo = "/folder/uploadinfo";
    pub const search = "/folder/search";
};

pub const item = struct {
    pub const details = "/item/details";
    pub const rename = "/item/rename";
    pub const delete = "/item/delete";
    pub const listall = "/item/listall";
};

pub const transfer = struct {
    pub const create = "/transfer/create";
    pub const directdl = "/transfer/directdl";
    pub const list = "/transfer/list";
    pub const retry = "/transfer/retry";
    pub const delete = "/transfer/delete";
    pub const clearfinished = "/transfer/clearfinished";
};

pub const cache = struct {
    pub const check = "/cache/check";
};

pub const services = struct {
    pub const list = "/services/list";
};
